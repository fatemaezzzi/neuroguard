// lib/core/services/location_service.dart
//
// LocationService — Patient Side (v2 — Write-Optimised)
// ─────────────────────────────────────────────────────────────────────────────
//
// WHAT CHANGED FROM v1
//
//  ① LIVE-LOCATION WRITE THROTTLE
//      _pushPosition() now gates Firestore writes to at most once every
//      [_liveLocationMinInterval] (default 60 seconds).
//
//      The patient's GPS stream still fires on every 20-metre movement
//      (distanceFilter: 20) — this is necessary for accurate safe-zone
//      breach detection which runs locally via _checkSafeZoneFromCache().
//      However, NOT every GPS fix needs to travel to Firestore. The caregiver's
//      map refreshes at human-visible speed; a 60-second cadence (≈ 1 write/min)
//      is indistinguishable from real-time on a map and cuts Firestore writes
//      by ~95 % versus per-fix writing.
//
//      Exception: a breach event (patient exits safe zone) always writes
//      immediately regardless of the throttle. The throttle timer is reset
//      at that point so the next routine write comes after a full interval.
//
//  ② NO OTHER LOGIC CHANGED
//      Safe-zone cache, breach detection, alert sending, caregiver read API,
//      permission handling — all unchanged.
//
// ARCHITECTURE NOTES
//   • History capture / Firestore sync cadence is owned by LocationHistoryService
//     (see that file). LocationService does NOT call LocationHistoryService.
//   • Geofence breach writes (_logBreachEvent, _checkSafeZoneFromCache) bypass
//     the throttle and always go immediately — they are rare and critical.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/alert_model.dart';
import 'alert_service.dart';

class LocationService {
  // ─── Singleton ────────────────────────────────────────────────────────────
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  // ─── Private State ────────────────────────────────────────────────────────
  StreamSubscription<Position>? _positionStream;
  StreamSubscription<DocumentSnapshot>? _docListener;
  bool _isTracking = false;
  bool _notificationsInitialised = false;
  String? _activePatientId;

  bool _safeZoneInitialised = false;

  DateTime? _lastBreachAlertTime;
  static const _breachAlertCooldown = Duration(minutes: 5);

  static const LocationSettings _locationSettings = LocationSettings(
    accuracy: LocationAccuracy.bestForNavigation,
    distanceFilter: 20,
  );

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ─── In-memory safe zone cache ────────────────────────────────────────────
  _CachedSafeZone? _cachedSafeZone;

  // ─── Live-location write throttle ────────────────────────────────────────
  // Limits liveLocation Firestore writes to at most once per interval.
  // Breach events always bypass this gate.
  static const Duration _liveLocationMinInterval = Duration(seconds: 60);
  DateTime? _lastLiveLocationWrite;

  // ─── Notifications ────────────────────────────────────────────────────────
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
  FlutterLocalNotificationsPlugin();

  // ──────────────────────────────────────────────────────────────────────────
  // STEP 1 — Initialise
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> initialise() async {
    if (_notificationsInitialised) return;
    _notificationsInitialised = true;
    await _initNotifications();
    await _requestPermissions();
  }

  Future<void> _initNotifications() async {
    const AndroidInitializationSettings androidSettings =
    AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
    );
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
    if (permission != LocationPermission.always) return false;

    return true;
  }

  Future<PermissionStatus> getPermissionStatus() async {
    final p = await Geolocator.checkPermission();
    switch (p) {
      case LocationPermission.always:
        return PermissionStatus.alwaysAllowed;
      case LocationPermission.whileInUse:
        return PermissionStatus.foregroundOnly;
      case LocationPermission.denied:
        return PermissionStatus.denied;
      case LocationPermission.deniedForever:
        return PermissionStatus.permanentlyDenied;
      default:
        return PermissionStatus.unknown;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // STEP 3 — Start / Stop Tracking
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> startTracking({required String patientId}) async {
    if (_isTracking && _activePatientId == patientId) return;
    if (_isTracking) stopTracking();

    if (!_isTracking) {
      final hasPermission = await _requestPermissions();
      if (!hasPermission) return;
    }

    _isTracking = true;
    _activePatientId = patientId;
    _lastLiveLocationWrite = null; // reset throttle on new session

    await _refreshSafeZoneCache(patientId);

    _docListener = _db
        .collection('users')
        .doc(patientId)
        .snapshots()
        .listen(_onDocSnapshot);

    _positionStream =
        Geolocator.getPositionStream(
          locationSettings: _locationSettings,
        ).listen(
              (Position pos) => _onNewPosition(patientId, pos),
          onError: (_) async {
            final last = await Geolocator.getLastKnownPosition();
            if (last != null) {
              await _pushPosition(patientId, last, isStale: true);
            }
          },
        );
  }

  Future<void> startTrackingForTesting({
    String testPatientId = 'test_patient_001',
  }) async {
    await startTracking(patientId: testPatientId);
  }

  void stopTracking() {
    _positionStream?.cancel();
    _docListener?.cancel();
    _positionStream = null;
    _docListener = null;
    _isTracking = false;
    _activePatientId = null;
    _cachedSafeZone = null;
    _safeZoneInitialised = false;
    _lastLiveLocationWrite = null;
  }

  bool get isTracking => _isTracking;
  String? get activePatientId => _activePatientId;

  // ──────────────────────────────────────────────────────────────────────────
  // STEP 4 — GPS Position Handler
  // ──────────────────────────────────────────────────────────────────────────

  void _onNewPosition(String patientId, Position pos) {
    // Discard fixes worse than 50 m accuracy — they're GPS noise.
    if (pos.accuracy > 50) return;
    _pushPosition(patientId, pos, isStale: false);
  }

  Future<void> _pushPosition(
      String patientId,
      Position pos, {
        required bool isStale,
      }) async {
    // ── Throttle gate ─────────────────────────────────────────────────────
    // Skip Firestore write if we pushed recently (within _liveLocationMinInterval).
    // Always run the local safe-zone check regardless of the gate.
    //
    // Breach events (isInsideZone flips false) bypass this gate — see
    // _checkSafeZoneFromCache which writes directly without going through here.
    final now = DateTime.now();
    final lastWrite = _lastLiveLocationWrite;
    final shouldWrite = lastWrite == null ||
        now.difference(lastWrite) >= _liveLocationMinInterval;

    // Always check safe zone locally — this is cheap and must not be throttled.
    _checkSafeZoneFromCache(patientId, pos);

    if (!shouldWrite) return; // skip Firestore write this cycle

    try {
      _lastLiveLocationWrite = now;
      await _db.collection('users').doc(patientId).set({
        'liveLocation': {
          'latitude': pos.latitude,
          'longitude': pos.longitude,
          'accuracy': pos.accuracy,
          'timestamp': FieldValue.serverTimestamp(),
          'speed': pos.speed,
          'heading': pos.heading,
          'isStale': isStale,
        },
      }, SetOptions(merge: true));
    } catch (e) {
      // Roll back the timestamp so the next movement attempt tries again.
      _lastLiveLocationWrite = lastWrite;
      assert(() {
        print('[LocationService] Push failed: $e');
        return true;
      }());
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
      centerLat: (sz['centerLat'] as num).toDouble(),
      centerLng: (sz['centerLng'] as num).toDouble(),
      radiusMeters: (sz['radiusMeters'] as num).toDouble(),
      wasInsideZone: sz['isInsideZone'] as bool? ?? true,
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
      pos.latitude,
      pos.longitude,
      cache.centerLat,
      cache.centerLng,
    );
    final bool isInside = dist <= cache.radiusMeters;

    if (isInside == cache.wasInsideZone) return;

    _cachedSafeZone = _CachedSafeZone(
      centerLat: cache.centerLat,
      centerLng: cache.centerLng,
      radiusMeters: cache.radiusMeters,
      wasInsideZone: isInside,
    );

    // Breach/return events always write immediately — reset the throttle
    // so the next routine live-location write follows a full interval after.
    _lastLiveLocationWrite = DateTime.now();

    _db
        .collection('users')
        .doc(patientId)
        .set({
      'safeZone': {
        'isInsideZone': isInside,
        'distanceFromCenter': dist,
        'lastBreachTime': isInside ? null : FieldValue.serverTimestamp(),
      },
    }, SetOptions(merge: true))
        .then((_) async {
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
        type: AlertType.geoFence,
        message: 'Patient is $distStr outside the safe zone.',
        severity: AlertSeverity.critical,
        metadata: {'distanceMeters': distMeters},
      ),
    );

    await Future.delayed(const Duration(seconds: 3));
    await AlertService().send(
      patientId: patientId,
      alert: AlertModel(
        type: AlertType.spyCall,
        message:
        'Patient is not in the safe zone. Do you want to make a quick spy call?',
        severity: AlertSeverity.warning,
        metadata: {'distanceMeters': distMeters},
      ),
    );
  }

  Future<void> _logBreachEvent(
      String patientId,
      Position pos,
      double dist,
      ) async {
    await _db
        .collection('users')
        .doc(patientId)
        .collection('breachEvents')
        .add({
      'latitude': pos.latitude,
      'longitude': pos.longitude,
      'distanceFromCenter': dist,
      'timestamp': FieldValue.serverTimestamp(),
      'acknowledged': false,
    });
  }

  // ──────────────────────────────────────────────────────────────────────────
  // STEP 6 — Caregiver Read API  (unchanged)
  // ──────────────────────────────────────────────────────────────────────────

  static Future<LocationSnapshot?> getPatientLocation(String patientId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(patientId)
          .get();
      final data = doc.data();
      if (data == null || data['liveLocation'] == null) return null;
      return _parse(data['liveLocation'] as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Stream<LocationSnapshot?> streamPatientLocation(String patientId) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(patientId)
        .snapshots()
        .map((doc) {
      final data = doc.data();
      if (data == null || data['liveLocation'] == null) return null;
      return _parse(data['liveLocation'] as Map<String, dynamic>);
    });
  }

  static LocationSnapshot _parse(Map<String, dynamic> loc) => LocationSnapshot(
    latitude: (loc['latitude'] as num).toDouble(),
    longitude: (loc['longitude'] as num).toDouble(),
    accuracy: (loc['accuracy'] as num?)?.toDouble() ?? 0.0,
    timestamp: (loc['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    isStale: loc['isStale'] as bool? ?? false,
    speed: (loc['speed'] as num?)?.toDouble() ?? 0.0,
  );
}

// ─── Internal cache model ─────────────────────────────────────────────────────
class _CachedSafeZone {
  final double centerLat;
  final double centerLng;
  final double radiusMeters;
  final bool wasInsideZone;
  const _CachedSafeZone({
    required this.centerLat,
    required this.centerLng,
    required this.radiusMeters,
    required this.wasInsideZone,
  });
}

// ─── Public Models ────────────────────────────────────────────────────────────

class LocationSnapshot {
  final double latitude;
  final double longitude;
  final double accuracy;
  final DateTime timestamp;
  final bool isStale;
  final double speed;

  const LocationSnapshot({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.timestamp,
    this.isStale = false,
    this.speed = 0.0,
  });

  int get minutesAgo => DateTime.now().difference(timestamp).inMinutes;

  String get freshnessLabel {
    final mins = minutesAgo;
    if (mins < 1) return 'Just now';
    if (mins < 60) return '${mins}m ago';
    final hours = (mins / 60).floor();
    if (hours < 24) return '${hours}h ${mins % 60}m ago';
    return '${(hours / 24).floor()}d ago';
  }

  String get accuracyLabel {
    if (accuracy <= 0) return '—';
    final meters = accuracy.toStringAsFixed(0);
    if (accuracy < 10) return '±${meters}m · Excellent';
    if (accuracy < 30) return '±${meters}m · Good';
    if (accuracy < 60) return '±${meters}m · Fair';
    return '±${meters}m · Poor';
  }

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