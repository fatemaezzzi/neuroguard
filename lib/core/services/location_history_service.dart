// lib/core/services/location_history_service.dart
//
// LocationHistoryService — Offline-First Location History
// ─────────────────────────────────────────────────────────────────────────────
//
// ARCHITECTURE
//   • All GPS fixes are written immediately to SQLite (sqflite) on the
//     patient's device — no network required.
//   • The background isolate (BackgroundTaskHandler) owns the capture + sync
//     cadence via its own tick counter. LocationService.startTracking() no
//     longer starts a Timer.periodic here — that caused a double-capture race
//     condition between the two isolates.
//   • captureAndSave() and syncNow() are called directly by the background
//     isolate on its own schedule.
//   • The caregiver's History page reads Firestore for remote history.
//     Local SQLite is only used for the patient's own device (offline fallback).
//
// WHY Timer.periodic WAS REMOVED
//   flutter_foreground_task runs in a separate Dart isolate. Singletons are
//   NOT shared across isolates — each isolate gets its own instance.
//   Having Timer.periodic in the main isolate AND a tick-based capture in the
//   background isolate caused two independent capture loops with separate
//   SQLite connections, leading to race conditions and missed Firestore syncs.
//   The background isolate is now the sole owner of the capture cadence.
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
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
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

  Map<String, dynamic> toFirestore() => {
    'patientId': patientId,
    'latitude': latitude,
    'longitude': longitude,
    'accuracy': accuracy,
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

  /// Push at most this many unsynced rows per sync run (avoids huge batches).
  static const int _syncBatchSize = 200;

  /// Keep at most this many rows locally (≈ 30 days at 15-min cadence).
  static const int _maxLocalRows = 2880;

  // ── State ─────────────────────────────────────────────────────────────────

  Database? _db;
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
        await db.execute(
          'CREATE INDEX idx_patient_time ON location_history(patient_id, recorded_at DESC)',
        );
      },
    );
    return _db!;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CAPTURE — called directly by BackgroundTaskHandler on its tick schedule
  // ─────────────────────────────────────────────────────────────────────────

  /// Gets current GPS position and saves to SQLite immediately.
  /// Called by BackgroundTaskHandler — NOT by a Timer.periodic anymore.
  Future<void> captureAndSave(String patientId) async {
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
      // AFTER getting the position, add this check:
      if (pos == null) return;

      // NEW: skip poor-accuracy fixes for history (jitter from cold GPS)
      if (pos.accuracy > 50) {
        // Try last known as fallback only if it's recent (< 10 min old)
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
    await db.insert(
      'location_history',
      entry.toSqlite(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // Trim oldest rows for this patient beyond the cap
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
  // READ — local SQLite (patient device only — not useful on caregiver side)
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
  // READ — Firestore (caregiver side — this is the primary read path)
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
  // SYNC — SQLite → Firestore
  // Called by BackgroundTaskHandler after every captureAndSave()
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> syncNow(String patientId) => _syncToFirestore(patientId);

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
      // No network or Firestore unavailable — will retry on next call
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DISPOSE
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> dispose() async {
    await _db?.close();
    _db = null;
  }
}
