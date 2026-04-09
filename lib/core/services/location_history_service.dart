// lib/core/services/location_history_service.dart
//
// LocationHistoryService — Offline-First Location History (v2 — Write-Optimised)
// ─────────────────────────────────────────────────────────────────────────────
//
// WHAT CHANGED FROM v1
//
//  ① SYNC DECOUPLED FROM CAPTURE
//      captureAndSave() no longer calls syncNow() on every tick.
//      An internal counter (_capturesSinceLastSync) auto-triggers sync
//      only after every [_capturesPerSyncCycle] captures (default 4 = 1 hour
//      at a 15-min cadence). BackgroundTaskHandler can also call syncNow()
//      directly on a separate hourly alarm — this is safe; the counter gate
//      prevents double-syncing.
//
//  ② RDP PATH COMPRESSION BEFORE FIRESTORE WRITES
//      _compressPath() runs Ramer-Douglas-Peucker on the pending batch before
//      writing to Firestore. Only geometrically significant keypoints are
//      uploaded; straight-line runs and idle jitter are dropped.
//      Typical savings: 96 raw points → 5–15 Firestore docs (~85–95 % fewer
//      writes). Full-resolution history is kept intact in SQLite.
//
//  ③ CONNECTIVITY GUARD
//      _isOnline() performs a DNS probe before any Firestore write. If the
//      device is offline, syncNow() returns immediately and retries next cycle.
//      No exceptions surface to the caller; no partial batch is left open.
//
//  ④ LIVE-LOCATION THROTTLE is handled separately in LocationService.
//      This service is history-only and does not touch the liveLocation field.
//
// DATABASE SCHEMA  (unchanged — no migration needed)
//   Table: location_history
//     id          INTEGER PRIMARY KEY AUTOINCREMENT
//     patient_id  TEXT    NOT NULL
//     latitude    REAL    NOT NULL
//     longitude   REAL    NOT NULL
//     accuracy    REAL
//     speed       REAL
//     heading     REAL
//     recorded_at TEXT    NOT NULL   -- ISO-8601 UTC, device clock
//     synced      INTEGER DEFAULT 0  -- 0 = pending, 1 = pushed to Firestore
//
// NEW DEPENDENCY (add to pubspec.yaml if not already present):
//   (none — dart:io is bundled; connectivity_plus is optional)
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

// ─── Public model ─────────────────────────────────────────────────────────────

class LocationHistoryEntry {
  final int? id; // SQLite row id (null when built from Firestore)
  final String patientId;
  final double latitude;
  final double longitude;
  final double accuracy;
  final double speed;
  final DateTime recordedAt;
  final bool synced;

  const LocationHistoryEntry({
    this.id,
    required this.patientId,
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.speed,
    required this.recordedAt,
    this.synced = false,
  });

  // ── SQLite ────────────────────────────────────────────────────────────────

  Map<String, dynamic> toSqlite() => {
    'patient_id': patientId,
    'latitude': latitude,
    'longitude': longitude,
    'accuracy': accuracy,
    'speed': speed,
    'recorded_at': recordedAt.toUtc().toIso8601String(),
    'synced': synced ? 1 : 0,
  };

  factory LocationHistoryEntry.fromSqlite(Map<String, dynamic> row) =>
      LocationHistoryEntry(
        id: row['id'] as int?,
        patientId: row['patient_id'] as String,
        latitude: row['latitude'] as double,
        longitude: row['longitude'] as double,
        accuracy: (row['accuracy'] as num?)?.toDouble() ?? 0.0,
        speed: (row['speed'] as num?)?.toDouble() ?? 0.0,
        recordedAt: DateTime.parse(row['recorded_at'] as String).toLocal(),
        synced: (row['synced'] as int? ?? 0) == 1,
      );

  // ── Firestore ─────────────────────────────────────────────────────────────
  // Only compressed keypoints are written. accuracy is omitted to keep
  // each document small — the caregiver map needs lat/lng/time/speed only.

  Map<String, dynamic> toFirestore() => {
    'patientId': patientId,
    'latitude': latitude,
    'longitude': longitude,
    'speed': speed,
    'recordedAt': Timestamp.fromDate(recordedAt.toUtc()),
  };

  factory LocationHistoryEntry.fromFirestore(
      DocumentSnapshot doc,
      String patientId,
      ) {
    final d = doc.data() as Map<String, dynamic>;
    return LocationHistoryEntry(
      patientId: patientId,
      latitude: (d['latitude'] as num).toDouble(),
      longitude: (d['longitude'] as num).toDouble(),
      accuracy: (d['accuracy'] as num?)?.toDouble() ?? 0.0,
      speed: (d['speed'] as num?)?.toDouble() ?? 0.0,
      recordedAt: (d['recordedAt'] as Timestamp).toDate().toLocal(),
      synced: true,
    );
  }
}

// ─── Service ──────────────────────────────────────────────────────────────────

class LocationHistoryService {
  // Singleton — NOTE: only meaningful within a single isolate.
  // The background isolate gets its own separate instance.
  static final LocationHistoryService _instance =
  LocationHistoryService._internal();
  factory LocationHistoryService() => _instance;
  LocationHistoryService._internal();

  // ── Config ────────────────────────────────────────────────────────────────

  /// Firestore batch ceiling — hard limit is 500 ops per batch.
  static const int _syncBatchSize = 200;

  /// Keep at most this many rows locally (≈ 30 days at 15-min cadence).
  static const int _maxLocalRows = 2880;

  /// RDP simplification threshold in metres.
  /// 15 m keeps meaningful turns while filtering stationary GPS jitter.
  static const double _rdpEpsilonMeters = 15.0;

  /// Captures between automatic sync attempts.
  /// 4 captures × 15 min cadence = 1 automatic sync per hour.
  static const int _capturesPerSyncCycle = 4;

  // ── State ─────────────────────────────────────────────────────────────────

  Database? _db;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Rolling counter; reset on every sync attempt (online or offline skip).
  int _capturesSinceLastSync = 0;

  // ─────────────────────────────────────────────────────────────────────────
  // SQLite initialisation
  // ─────────────────────────────────────────────────────────────────────────

  Future<Database> _getDb() async {
    if (_db != null) return _db!;
    final dbPath = p.join(await getDatabasesPath(), 'neuroguard_location.db');
    _db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE location_history (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            patient_id  TEXT    NOT NULL,
            latitude    REAL    NOT NULL,
            longitude   REAL    NOT NULL,
            accuracy    REAL,
            speed       REAL,
            heading     REAL,
            recorded_at TEXT    NOT NULL,
            synced      INTEGER DEFAULT 0
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_patient_time ON location_history(patient_id, recorded_at DESC)',
        );
      },
    );
    return _db!;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CAPTURE — called by BackgroundTaskHandler on its 15-min tick
  // ─────────────────────────────────────────────────────────────────────────

  /// Captures a GPS fix and saves it to SQLite immediately.
  ///
  /// Does NOT push to Firestore on every call. Sync is triggered automatically
  /// once every [_capturesPerSyncCycle] calls (~1 hour at 15-min cadence).
  /// BackgroundTaskHandler may also call [syncNow] directly on its own hourly
  /// alarm — safe; the counter gate prevents double-syncing.
  Future<void> captureAndSave(String patientId) async {
    try {
      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
          timeLimit: const Duration(seconds: 12),
        );
      } catch (_) {
        pos = await Geolocator.getLastKnownPosition();
      }
      if (pos == null) return;

      // Skip poor-accuracy fixes — GPS cold-start jitter looks like movement.
      if (pos.accuracy > 50) {
        final alt = await Geolocator.getLastKnownPosition();
        if (alt == null || alt.accuracy > 50) return;
        pos = alt;
      }

      final entry = LocationHistoryEntry(
        patientId: patientId,
        latitude: pos.latitude,
        longitude: pos.longitude,
        accuracy: pos.accuracy,
        speed: pos.speed.clamp(0.0, double.infinity),
        recordedAt: DateTime.now(),
        synced: false,
      );

      await saveEntry(entry);
      _capturesSinceLastSync++;

      // Auto-trigger sync after every [_capturesPerSyncCycle] captures.
      if (_capturesSinceLastSync >= _capturesPerSyncCycle) {
        await syncNow(patientId);
      }
    } catch (_) {
      // Never crash the background task.
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // WRITE — local SQLite only
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> saveEntry(LocationHistoryEntry entry) async {
    final db = await _getDb();
    await db.insert(
      'location_history',
      entry.toSqlite(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // Trim rows beyond the cap to prevent unbounded growth.
    await db.execute(
      '''
      DELETE FROM location_history
      WHERE patient_id = ? AND id NOT IN (
        SELECT id FROM location_history
        WHERE patient_id = ?
        ORDER BY recorded_at DESC
        LIMIT ?
      )
    ''',
      [entry.patientId, entry.patientId, _maxLocalRows],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // READ — local SQLite (patient device only)
  // ─────────────────────────────────────────────────────────────────────────

  Future<List<LocationHistoryEntry>> getLocalHistory({
    required String patientId,
    int limit = 96,
    DateTime? from,
    DateTime? to,
  }) async {
    final db = await _getDb();
    String where = 'patient_id = ?';
    List<dynamic> args = [patientId];

    if (from != null) {
      where += ' AND recorded_at >= ?';
      args.add(from.toUtc().toIso8601String());
    }
    if (to != null) {
      where += ' AND recorded_at <= ?';
      args.add(to.toUtc().toIso8601String());
    }

    final rows = await db.query(
      'location_history',
      where: where,
      whereArgs: args,
      orderBy: 'recorded_at DESC',
      limit: limit,
    );

    return rows.map(LocationHistoryEntry.fromSqlite).toList();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // READ — Firestore (caregiver side — compressed keypoints)
  // ─────────────────────────────────────────────────────────────────────────

  Future<List<LocationHistoryEntry>> getRemoteHistory({
    required String patientId,
    int limit = 96,
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      Query query = _firestore
          .collection('users')
          .doc(patientId)
          .collection('locationHistory')
          .orderBy('recordedAt', descending: true)
          .limit(limit);

      if (from != null) {
        query = query.where(
          'recordedAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(from.toUtc()),
        );
      }
      if (to != null) {
        query = query.where(
          'recordedAt',
          isLessThanOrEqualTo: Timestamp.fromDate(to.toUtc()),
        );
      }

      final snapshot = await query.get();
      return snapshot.docs
          .map((d) => LocationHistoryEntry.fromFirestore(d, patientId))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SYNC — SQLite → Firestore  (RDP-compressed, connectivity-guarded)
  // ─────────────────────────────────────────────────────────────────────────

  /// Compresses pending raw history with RDP and writes only the keypoints
  /// to Firestore. No-ops silently when the device is offline.
  ///
  /// Safe to call at any frequency — the internal counter is always reset so
  /// the next automatic cycle starts fresh.
  Future<void> syncNow(String patientId) async {
    _capturesSinceLastSync = 0; // reset regardless of online/offline
    if (!await _isOnline()) return;
    await _syncToFirestore(patientId);
  }

  Future<void> _syncToFirestore(String patientId) async {
    try {
      final db = await _getDb();

      final rows = await db.query(
        'location_history',
        where: 'patient_id = ? AND synced = 0',
        whereArgs: [patientId],
        orderBy: 'recorded_at ASC',
        limit: _syncBatchSize,
      );

      if (rows.isEmpty) return;

      final entries = rows.map(LocationHistoryEntry.fromSqlite).toList();
      final ids = rows.map((r) => r['id'] as int).toList();

      // ── RDP path compression ──────────────────────────────────────────────
      // Reduces the raw path to meaningful turning-points only.
      //   • 4 points over 1 h stationary → 0–2 Firestore docs
      //   • 96 points over 24 h of walking → typically 10–20 Firestore docs
      // Full-resolution data stays in SQLite for local playback.
      final keypoints = _compressPath(entries, epsilon: _rdpEpsilonMeters);

      if (keypoints.isNotEmpty) {
        final batch = _firestore.batch();
        final historyCol = _firestore
            .collection('users')
            .doc(patientId)
            .collection('locationHistory');

        for (final entry in keypoints) {
          batch.set(historyCol.doc(), entry.toFirestore());
        }
        await batch.commit();
      }

      // Mark ALL fetched raw rows as synced (not just the compressed subset).
      await _markSynced(db, ids);
    } catch (_) {
      // Firestore unavailable — rows stay unsynced; retry next cycle.
    }
  }

  Future<void> _markSynced(Database db, List<int> ids) async {
    if (ids.isEmpty) return;
    final placeholders = ids.map((_) => '?').join(',');
    await db.rawUpdate(
      'UPDATE location_history SET synced = 1 WHERE id IN ($placeholders)',
      ids,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CONNECTIVITY GUARD
  // ─────────────────────────────────────────────────────────────────────────

  /// DNS probe — more reliable than connectivity_plus on captive portals.
  /// Resolves in < 500 ms on a live connection; throws when truly offline.
  Future<bool> _isOnline() async {
    try {
      final result = await InternetAddress.lookup('firestore.googleapis.com')
          .timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PATH COMPRESSION — Ramer-Douglas-Peucker (RDP)
  // ─────────────────────────────────────────────────────────────────────────
  //
  // Iteratively splits the polyline at the point of maximum perpendicular
  // distance from the current segment. Points within [epsilon] metres are
  // considered collinear / idle drift and discarded.
  //
  // Always retains first and last points — the synced history is bookended
  // regardless of how far the patient moved.
  //
  // Complexity: O(n log n) on average; O(n²) worst-case on perfectly zigzag
  // paths. For n ≤ 200 (our batch cap) this is always fast.
  // ─────────────────────────────────────────────────────────────────────────

  static List<LocationHistoryEntry> _compressPath(
      List<LocationHistoryEntry> points, {
        required double epsilon,
      }) {
    if (points.length <= 2) return List.of(points);

    double maxDist = 0.0;
    int maxIndex = 0;

    for (int i = 1; i < points.length - 1; i++) {
      final d = _perpendicularDistanceMeters(
        points[i],
        points.first,
        points.last,
      );
      if (d > maxDist) {
        maxDist = d;
        maxIndex = i;
      }
    }

    if (maxDist > epsilon) {
      final left = _compressPath(
        points.sublist(0, maxIndex + 1),
        epsilon: epsilon,
      );
      final right = _compressPath(
        points.sublist(maxIndex),
        epsilon: epsilon,
      );
      // Merge: left already ends at maxIndex; right starts at maxIndex — dedup.
      return [...left.sublist(0, left.length - 1), ...right];
    }

    // All interior points within epsilon — keep only endpoints.
    return [points.first, points.last];
  }

  /// Perpendicular distance in metres from [pt] to the segment [a]→[b].
  ///
  /// Uses a flat-earth (local tangent plane) approximation accurate to
  /// < 0.5 % for distances under ~50 km — more than sufficient for
  /// patient-tracking scenarios.
  static double _perpendicularDistanceMeters(
      LocationHistoryEntry pt,
      LocationHistoryEntry a,
      LocationHistoryEntry b,
      ) {
    const double kMetersPerDeg = 111320.0;
    final double cosLat = math.cos(pt.latitude * math.pi / 180.0);

    final double ax = a.longitude * kMetersPerDeg * cosLat;
    final double ay = a.latitude * kMetersPerDeg;
    final double bx = b.longitude * kMetersPerDeg * cosLat;
    final double by = b.latitude * kMetersPerDeg;
    final double px = pt.longitude * kMetersPerDeg * cosLat;
    final double py = pt.latitude * kMetersPerDeg;

    final double dx = bx - ax;
    final double dy = by - ay;

    if (dx == 0.0 && dy == 0.0) {
      // a == b: return distance to that single point.
      return math.sqrt((px - ax) * (px - ax) + (py - ay) * (py - ay));
    }

    // Perpendicular distance = |cross product ab × ap| / |ab|
    final double cross = (px - ax) * dy - (py - ay) * dx;
    final double len = math.sqrt(dx * dx + dy * dy);
    return cross.abs() / len;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DISPOSE
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> dispose() async {
    await _db?.close();
    _db = null;
  }
}