// lib/core/services/location_history_service.dart
//
// LocationHistoryService — Offline-First Location History
// ─────────────────────────────────────────────────────────────────────────────
//
// ARCHITECTURE
//   • All GPS fixes are written immediately to SQLite (sqflite) on the
//     patient's device — no network required.
//   • A background sync job runs whenever connectivity is available and
//     pushes unsynced rows into Firestore  users/{id}/locationHistory.
//   • The caregiver's History page reads Firestore for remote history, but
//     falls back to the local SQLite when offline (shared through this service).
//
// PERIODIC TRACKING (15-minute cadence)
//   • startPeriodicTracking() sets up a 15-minute Timer.periodic that calls
//     _captureAndSave() regardless of whether the patient has moved.
//     This guarantees at least one fix per 15-minute window even if the
//     Geolocator stream is paused or the distance filter is active.
//
// DATABASE SCHEMA
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
// DEPENDENCIES (add to pubspec.yaml if not already present):
//   sqflite: ^2.3.3
//   path: ^1.9.0
//   connectivity_plus: ^6.0.3
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

// ─── Public model ─────────────────────────────────────────────────────────────

class LocationHistoryEntry {
  final int?     id;          // SQLite row id (null when built from Firestore)
  final String   patientId;
  final double   latitude;
  final double   longitude;
  final double   accuracy;
  final double   speed;
  final DateTime recordedAt;
  final bool     synced;

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
    'patient_id':  patientId,
    'latitude':    latitude,
    'longitude':   longitude,
    'accuracy':    accuracy,
    'speed':       speed,
    'recorded_at': recordedAt.toUtc().toIso8601String(),
    'synced':      synced ? 1 : 0,
  };

  factory LocationHistoryEntry.fromSqlite(Map<String, dynamic> row) =>
      LocationHistoryEntry(
        id:         row['id'] as int?,
        patientId:  row['patient_id'] as String,
        latitude:   row['latitude'] as double,
        longitude:  row['longitude'] as double,
        accuracy:   (row['accuracy'] as num?)?.toDouble() ?? 0.0,
        speed:      (row['speed']    as num?)?.toDouble() ?? 0.0,
        recordedAt: DateTime.parse(row['recorded_at'] as String).toLocal(),
        synced:     (row['synced'] as int? ?? 0) == 1,
      );

  // ── Firestore ─────────────────────────────────────────────────────────────

  Map<String, dynamic> toFirestore() => {
    'patientId':  patientId,
    'latitude':   latitude,
    'longitude':  longitude,
    'accuracy':   accuracy,
    'speed':      speed,
    'recordedAt': Timestamp.fromDate(recordedAt.toUtc()),
  };

  factory LocationHistoryEntry.fromFirestore(
      DocumentSnapshot doc, String patientId) {
    final d = doc.data() as Map<String, dynamic>;
    return LocationHistoryEntry(
      patientId:  patientId,
      latitude:   (d['latitude']  as num).toDouble(),
      longitude:  (d['longitude'] as num).toDouble(),
      accuracy:   (d['accuracy']  as num?)?.toDouble() ?? 0.0,
      speed:      (d['speed']     as num?)?.toDouble() ?? 0.0,
      recordedAt: (d['recordedAt'] as Timestamp).toDate().toLocal(),
      synced:     true,
    );
  }
}

// ─── Service ──────────────────────────────────────────────────────────────────

class LocationHistoryService {
  // Singleton
  static final LocationHistoryService _instance =
  LocationHistoryService._internal();
  factory LocationHistoryService() => _instance;
  LocationHistoryService._internal();

  // ── Config ────────────────────────────────────────────────────────────────

  static const Duration _periodicInterval = Duration(minutes: 15);

  /// Keep at most this many rows locally (≈ 30 days at 15-min cadence).
  static const int _maxLocalRows = 2880;

  /// Push at most this many unsynced rows per sync run (avoids huge batches).
  static const int _syncBatchSize = 200;

  // ── State ─────────────────────────────────────────────────────────────────

  Database?      _db;
  Timer?         _periodicTimer;
  Timer?         _syncTimer;
  String?        _activePatientId;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ─────────────────────────────────────────────────────────────────────────
  // Initialise SQLite
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
        // Index for fast patient queries
        await db.execute(
          'CREATE INDEX idx_patient_time ON location_history(patient_id, recorded_at DESC)',
        );
      },
    );
    return _db!;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // START / STOP
  // ─────────────────────────────────────────────────────────────────────────

  /// Call this once from LocationService.startTracking().
  /// Begins the 15-minute periodic capture loop.
  Future<void> startPeriodicTracking({required String patientId}) async {
    if (_activePatientId == patientId && _periodicTimer != null) return;

    stopPeriodicTracking(); // cancel any previous patient session
    _activePatientId = patientId;

    // Capture immediately, then every 15 minutes
    await _captureAndSave(patientId);

    _periodicTimer = Timer.periodic(_periodicInterval, (_) async {
      await _captureAndSave(patientId);
    });

    // Attempt a Firestore sync every 5 minutes (best-effort)
    _syncTimer = Timer.periodic(const Duration(minutes: 5), (_) async {
      await _syncToFirestore(patientId);
    });
  }

  void stopPeriodicTracking() {
    _periodicTimer?.cancel();
    _syncTimer?.cancel();
    _periodicTimer    = null;
    _syncTimer        = null;
    _activePatientId  = null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CAPTURE
  // ─────────────────────────────────────────────────────────────────────────

  /// Gets current GPS position and saves to SQLite immediately.
  Future<void> _captureAndSave(String patientId) async {
    try {
      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
          timeLimit: const Duration(seconds: 12),
        );
      } catch (_) {
        // Fallback to last known position if GPS is momentarily unavailable
        pos = await Geolocator.getLastKnownPosition();
      }
      if (pos == null) return;

      final entry = LocationHistoryEntry(
        patientId:  patientId,
        latitude:   pos.latitude,
        longitude:  pos.longitude,
        accuracy:   pos.accuracy,
        speed:      pos.speed.clamp(0.0, double.infinity),
        recordedAt: DateTime.now(),
        synced:     false,
      );

      await saveEntry(entry);
    } catch (_) {
      // Silently ignore — periodic capture should never crash the caller
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // WRITE — local SQLite
  // ─────────────────────────────────────────────────────────────────────────

  /// Saves a location entry to the local SQLite database.
  /// Also trims the table to [_maxLocalRows] to prevent unbounded growth.
  Future<void> saveEntry(LocationHistoryEntry entry) async {
    final db = await _getDb();
    await db.insert('location_history', entry.toSqlite(),
        conflictAlgorithm: ConflictAlgorithm.replace);

    // Trim oldest rows for this patient beyond the cap
    await db.execute('''
      DELETE FROM location_history
      WHERE patient_id = ? AND id NOT IN (
        SELECT id FROM location_history
        WHERE patient_id = ?
        ORDER BY recorded_at DESC
        LIMIT ?
      )
    ''', [entry.patientId, entry.patientId, _maxLocalRows]);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // READ — local SQLite
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns the most recent [limit] history entries from the local DB.
  Future<List<LocationHistoryEntry>> getLocalHistory({
    required String patientId,
    int limit  = 96,          // default: last 24 hours at 15-min cadence
    DateTime? from,
    DateTime? to,
  }) async {
    final db = await _getDb();

    String where      = 'patient_id = ?';
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
      where:   where,
      whereArgs: args,
      orderBy: 'recorded_at DESC',
      limit:   limit,
    );

    return rows.map(LocationHistoryEntry.fromSqlite).toList();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // READ — Firestore (caregiver side / when online)
  // ─────────────────────────────────────────────────────────────────────────

  /// Fetches location history from Firestore for the given patient.
  /// Used by the caregiver's HistoryPage when the device is online.
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
  // SYNC — SQLite → Firestore
  // ─────────────────────────────────────────────────────────────────────────

  /// Pushes unsynced local rows to Firestore in batches.
  /// Marks each successfully pushed row as synced in SQLite.
  Future<void> _syncToFirestore(String patientId) async {
    try {
      final db = await _getDb();

      final rows = await db.query(
        'location_history',
        where:     'patient_id = ? AND synced = 0',
        whereArgs: [patientId],
        orderBy:   'recorded_at ASC',
        limit:     _syncBatchSize,
      );

      if (rows.isEmpty) return;

      final entries = rows.map(LocationHistoryEntry.fromSqlite).toList();

      // Firestore batch write (max 500 ops per batch — well within limit here)
      final batch = _firestore.batch();
      final historyCol = _firestore
          .collection('users')
          .doc(patientId)
          .collection('locationHistory');

      for (final entry in entries) {
        batch.set(historyCol.doc(), entry.toFirestore());
      }
      await batch.commit();

      // Mark as synced in SQLite
      final ids = rows.map((r) => r['id'] as int).toList();
      final placeholders = ids.map((_) => '?').join(',');
      await db.rawUpdate(
        'UPDATE location_history SET synced = 1 WHERE id IN ($placeholders)',
        ids,
      );
    } catch (_) {
      // No network or Firestore unavailable — will retry on next timer tick
    }
  }

  /// Public method so caller can trigger a one-shot sync (e.g. on app resume).
  Future<void> syncNow(String patientId) => _syncToFirestore(patientId);

  // ─────────────────────────────────────────────────────────────────────────
  // DISPOSE
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> dispose() async {
    stopPeriodicTracking();
    await _db?.close();
    _db = null;
  }
}