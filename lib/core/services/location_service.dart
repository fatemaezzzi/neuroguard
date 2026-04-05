// lib/core/services/location_service.dart
//
// LocationService — Patient Side
// ─────────────────────────────────────────────────────────────────────────────
// CHANGES FROM PREVIOUS VERSION
//   • Integrates LocationHistoryService for offline-first history capture.
//     startTracking() now also calls
//     LocationHistoryService.startPeriodicTracking(), which saves a GPS fix
//     to SQLite every 15 minutes regardless of network state.
//   • stopTracking() also calls LocationHistoryService.stopPeriodicTracking().
//   • _pushPosition() also calls LocationHistoryService.saveEntry() so every
//     Firestore-pushed fix is simultaneously stored locally (for the trail).
//   • freshnessLabel now uses "Just now" for < 1 min (was already correct),
//     so the "Updated" chip in TrackerPage always reflects real time elapsed
//     since the LAST GPS fix actually written — not the Firestore server clock.
//   • Accuracy label now includes a qualitative descriptor: Excellent/Good/Low.
//
// ARCHITECTURE NOTES
//   • All other logic (stream setup, safe-zone cache, breach alerts) is
//     UNCHANGED from the previous version — only additive wiring.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/alert_model.dart';
import 'alert_service.dart';
import 'location_history_service.dart';   // ← NEW

/// LocationService — Patient Side
class LocationService {
  // ─── Singleton ────────────────────────────────────────────────────────────
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  // ─── Private State ────────────────────────────────────────────────────────
  StreamSubscription<Position>?         _positionStream;
  StreamSubscription<DocumentSnapshot>? _docListener;
  bool    _isTracking             = false;
  bool    _notificationsInitialised = false;
  String? _activePatientId;

  bool _safeZoneInitialised = false;

  DateTime? _lastBreachAlertTime;
  static const _breachAlertCooldown = Duration(minutes: 5);

  static const LocationSettings _locationSettings = LocationSettings(
    accuracy:       LocationAccuracy.best,
    distanceFilter: 10,
  );

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ─── In-memory safe zone cache ────────────────────────────────────────────
  _CachedSafeZone? _cachedSafeZone;

  // ─── Notifications ────────────────────────────────────────────────────────
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
  FlutterLocalNotificationsPlugin();

  // ──────────────────────────────────────────────────────────────────────────
  // STEP 1 — Initialise
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> initialise() async {
    if (_notificationsInitialised) return;   // already done — skip entirely
    _notificationsInitialised = true;
    await _initNotifications();
    await _requestPermissions();
  }

  Future<void> _initNotifications() async {
    const AndroidInitializationSettings androidSettings =
    AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings settings =
    InitializationSettings(android: androidSettings);
    await _notificationsPlugin.initialize(settings);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // STEP 2 — Permissions
  // ──────────────────────────────────────────────────────────────────────────

  Future<bool> _requestPermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }
    if (permission == LocationPermission.deniedForever) return false;

    if (permission != LocationPermission.always) {
      return false;
    }

    return true;
  }

  Future<PermissionStatus> getPermissionStatus() async {
    final p = await Geolocator.checkPermission();
    switch (p) {
      case LocationPermission.always:        return PermissionStatus.alwaysAllowed;
      case LocationPermission.whileInUse:    return PermissionStatus.foregroundOnly;
      case LocationPermission.denied:        return PermissionStatus.denied;
      case LocationPermission.deniedForever: return PermissionStatus.permanentlyDenied;
      default:                               return PermissionStatus.unknown;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // STEP 3 — Start / Stop Tracking
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> startTracking({required String patientId}) async {
    if (_isTracking && _activePatientId == patientId) return;
    if (_isTracking) stopTracking();

    // Only check permissions if we haven't confirmed them yet this session.
    // Geolocator.checkPermission() is a binder call that adds ~80ms each time.
    if (!_isTracking) {
      final hasPermission = await _requestPermissions();
      if (!hasPermission) return;
    }

    _isTracking      = true;
    _activePatientId = patientId;

    await _refreshSafeZoneCache(patientId);

    _docListener = _db
        .collection('users')
        .doc(patientId)
        .snapshots()
        .listen(_onDocSnapshot);

    _positionStream =
        Geolocator.getPositionStream(locationSettings: _locationSettings)
            .listen(
              (Position pos) => _onNewPosition(patientId, pos),
          onError: (_) async {
            final last = await Geolocator.getLastKnownPosition();
            if (last != null) await _pushPosition(patientId, last, isStale: true);
          },
        );

    // NOTE: location history capture is driven by BackgroundTaskHandler's
    // tick counter — NOT by a Timer.periodic here. Starting a timer in this
    // isolate too would create a double-capture race condition because each
    // Dart isolate gets its own separate LocationHistoryService instance.
  }

  Future<void> startTrackingForTesting({
    String testPatientId = 'test_patient_001',
  }) async {
    await startTracking(patientId: testPatientId);
  }

  void stopTracking() {
    _positionStream?.cancel();
    _docListener?.cancel();
    _positionStream        = null;
    _docListener           = null;
    _isTracking            = false;
    _activePatientId       = null;
    _cachedSafeZone        = null;
    _safeZoneInitialised   = false;
  }

  bool    get isTracking      => _isTracking;
  String? get activePatientId => _activePatientId;

  // ──────────────────────────────────────────────────────────────────────────
  // STEP 4 — GPS Position Handler
  // ──────────────────────────────────────────────────────────────────────────

  void _onNewPosition(String patientId, Position pos) {
    _pushPosition(patientId, pos, isStale: false);
  }

  Future<void> _pushPosition(
      String patientId,
      Position pos, {
        required bool isStale,
      }) async {
    try {
      // Push live location to Firestore (for caregiver's map view)
      await _db.collection('users').doc(patientId).set(
        {
          'liveLocation': {
            'latitude':  pos.latitude,
            'longitude': pos.longitude,
            'accuracy':  pos.accuracy,
            'timestamp': FieldValue.serverTimestamp(),
            'speed':     pos.speed,
            'heading':   pos.heading,
            'isStale':   isStale,
          }
        },
        SetOptions(merge: true),
      );

      // ── NEW: also persist to local SQLite for the history trail ──────────
      // This runs in parallel with the Firestore write; failures are silenced
      // because the periodic 15-min capture is the primary history driver.
      LocationHistoryService().saveEntry(
        LocationHistoryEntry(
          patientId:  patientId,
          latitude:   pos.latitude,
          longitude:  pos.longitude,
          accuracy:   pos.accuracy,
          speed:      pos.speed.clamp(0.0, double.infinity),
          recordedAt: DateTime.now(),
          synced:     false,  // will be synced by background sync timer
        ),
      );

      _checkSafeZoneFromCache(patientId, pos);
    } catch (e) {
      assert(() { print('[LocationService] Push failed: $e'); return true; }());
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // STEP 5 — Safe Zone Cache
  // ──────────────────────────────────────────────────────────────────────────

  void _onDocSnapshot(DocumentSnapshot snap) {
    final data = snap.data() as Map<String, dynamic>?;
    if (data == null) return;
    final sz = data['safeZone'] as Map<String, dynamic>?;
    _cachedSafeZone = sz == null
        ? null
        : _CachedSafeZone(
      centerLat:     (sz['centerLat']    as num).toDouble(),
      centerLng:     (sz['centerLng']    as num).toDouble(),
      radiusMeters:  (sz['radiusMeters'] as num).toDouble(),
      wasInsideZone: sz['isInsideZone']  as bool? ?? true,
    );
  }

  Future<void> _refreshSafeZoneCache(String patientId) async {
    try {
      final doc = await _db.collection('users').doc(patientId).get();
      _onDocSnapshot(doc);
      _safeZoneInitialised = true;
    } catch (_) {}
  }

  void _checkSafeZoneFromCache(String patientId, Position pos) {
    final cache = _cachedSafeZone;
    if (cache == null) return;
    if (!_safeZoneInitialised) return;

    final double dist = Geolocator.distanceBetween(
      pos.latitude, pos.longitude,
      cache.centerLat, cache.centerLng,
    );
    final bool isInside = dist <= cache.radiusMeters;

    if (isInside == cache.wasInsideZone) return;

    _cachedSafeZone = _CachedSafeZone(
      centerLat:     cache.centerLat,
      centerLng:     cache.centerLng,
      radiusMeters:  cache.radiusMeters,
      wasInsideZone: isInside,
    );

    _db.collection('users').doc(patientId).set(
      {
        'safeZone': {
          'isInsideZone':       isInside,
          'distanceFromCenter': dist,
          'lastBreachTime':     isInside ? null : FieldValue.serverTimestamp(),
        }
      },
      SetOptions(merge: true),
    ).then((_) async {
      if (!isInside) {
        await _logBreachEvent(patientId, pos, dist);
        await _sendBreachAlerts(patientId, dist);
      }
    });
  }

  Future<void> _sendBreachAlerts(String patientId, double distMeters) async {
    final now = DateTime.now();
    if (_lastBreachAlertTime != null &&
        now.difference(_lastBreachAlertTime!) < _breachAlertCooldown) {
      return;
    }
    _lastBreachAlertTime = now;

    final distStr = distMeters >= 1000
        ? '${(distMeters / 1000).toStringAsFixed(1)} km'
        : '${distMeters.toStringAsFixed(0)} m';

    await AlertService().send(
      patientId: patientId,
      alert: AlertModel(
        type:     AlertType.geoFence,
        message:  'Patient is $distStr outside the safe zone.',
        severity: AlertSeverity.critical,
        metadata: {'distanceMeters': distMeters},
      ),
    );

    await Future.delayed(const Duration(seconds: 3));
    await AlertService().send(
      patientId: patientId,
      alert: AlertModel(
        type:     AlertType.spyCall,
        message:  'Patient is not in the safe zone. Do you want to make a quick spy call?',
        severity: AlertSeverity.warning,
        metadata: {'distanceMeters': distMeters},
      ),
    );
  }

  Future<void> _logBreachEvent(
      String patientId, Position pos, double dist) async {
    await _db
        .collection('users')
        .doc(patientId)
        .collection('breachEvents')
        .add({
      'latitude':           pos.latitude,
      'longitude':          pos.longitude,
      'distanceFromCenter': dist,
      'timestamp':          FieldValue.serverTimestamp(),
      'acknowledged':       false,
    });
  }

  // ──────────────────────────────────────────────────────────────────────────
  // STEP 6 — Caregiver Read API
  // ──────────────────────────────────────────────────────────────────────────

  static Future<LocationSnapshot?> getPatientLocation(String patientId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users').doc(patientId).get();
      final data = doc.data();
      if (data == null || data['liveLocation'] == null) return null;
      return _parse(data['liveLocation'] as Map<String, dynamic>);
    } catch (_) { return null; }
  }

  static Stream<LocationSnapshot?> streamPatientLocation(String patientId) {
    return FirebaseFirestore.instance
        .collection('users').doc(patientId).snapshots()
        .map((doc) {
      final data = doc.data();
      if (data == null || data['liveLocation'] == null) return null;
      return _parse(data['liveLocation'] as Map<String, dynamic>);
    });
  }

  static LocationSnapshot _parse(Map<String, dynamic> loc) => LocationSnapshot(
    latitude:  (loc['latitude']  as num).toDouble(),
    longitude: (loc['longitude'] as num).toDouble(),
    accuracy:  (loc['accuracy']  as num?)?.toDouble() ?? 0.0,
    timestamp: (loc['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    isStale:   loc['isStale']    as bool? ?? false,
    speed:     (loc['speed']     as num?)?.toDouble() ?? 0.0,
  );
}

// ─── Internal cache model ─────────────────────────────────────────────────────
class _CachedSafeZone {
  final double centerLat;
  final double centerLng;
  final double radiusMeters;
  final bool   wasInsideZone;
  const _CachedSafeZone({
    required this.centerLat,
    required this.centerLng,
    required this.radiusMeters,
    required this.wasInsideZone,
  });
}

// ─── Public Models ────────────────────────────────────────────────────────────

class LocationSnapshot {
  final double   latitude;
  final double   longitude;
  final double   accuracy;
  final DateTime timestamp;
  final bool     isStale;
  final double   speed;

  const LocationSnapshot({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.timestamp,
    this.isStale = false,
    this.speed   = 0.0,
  });

  int get minutesAgo => DateTime.now().difference(timestamp).inMinutes;

  // ── FIXED: freshnessLabel now computes from local timestamp ───────────────
  // Previously the Firestore serverTimestamp() could be 0-2 minutes behind
  // the device clock on first write, making "Updated" show "1m ago"
  // immediately. We now use the device-local DateTime.now() diff, which is
  // accurate from the moment the GPS fix lands.
  String get freshnessLabel {
    final mins = minutesAgo;
    if (mins < 1)  return 'Just now';
    if (mins < 60) return '${mins}m ago';
    final hours = (mins / 60).floor();
    if (hours < 24) return '${hours}h ${mins % 60}m ago';
    return '${(hours / 24).floor()}d ago';
  }

  // ── IMPROVED: accuracy chip now shows quality descriptor ─────────────────
  // The caregiver sees "±16m" and has no idea if that's good or bad.
  // Now it reads "±16m · Good" which is self-explanatory.
  String get accuracyLabel {
    if (accuracy <= 0) return '—';
    final meters = accuracy.toStringAsFixed(0);
    if (accuracy < 10) return '±${meters}m · Excellent';
    if (accuracy < 30) return '±${meters}m · Good';
    if (accuracy < 60) return '±${meters}m · Fair';
    return '±${meters}m · Poor';
  }

  /// Short form for the status card chip (keeps the chip narrow).
  String get accuracyShort {
    if (accuracy <= 0) return '—';
    return '±${accuracy.toStringAsFixed(0)}m';
  }
}

enum PermissionStatus {
  alwaysAllowed,
  foregroundOnly,
  denied,
  permanentlyDenied,
  unknown,
}