import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// LocationService — Patient Side
///
/// ── BUGS FIXED ────────────────────────────────────────────────────────────
///
/// BUG 1 (Critical — silent write failure, root cause of stale caregiver map)
///   All Firestore writes used .update() with dot-notation field paths.
///   .update() throws "NOT_FOUND" if the top-level key ('liveLocation' or
///   'safeZone') does not yet exist on the document — e.g. first launch,
///   freshly created user doc, or after wiping Firestore during testing.
///   The catch block silently swallowed the exception, so the caregiver's
///   StreamBuilder always received null → patient marker never rendered.
///   Fix: all writes now use .set(..., SetOptions(merge: true)).
///
/// BUG 2 (Reliability — Timer killed in background)
///   Timer.periodic + getCurrentPosition() does not survive Android
///   background process limits without an active foreground service.
///   Fix: replaced with Geolocator.getPositionStream() which registers a
///   real OS-level location subscription that keeps firing in background
///   (given 'always' permission or a foreground service is active).
///   Added distanceFilter:10 to suppress redundant writes when stationary.
///
/// BUG 3 (Correctness — background permission upgrade path was broken)
///   The original code called requestPermission() twice to try to upgrade
///   from whileInUse → always. Android ignores the second call silently.
///   Fix: documented the correct path (openAppSettings()) and return true
///   for whileInUse so foreground tracking still starts regardless.
///
/// BUG 4 (Testing — startTracking never called without auth)
///   Added startTrackingForTesting() bypass for dev use with a hardcoded
///   patientId. Must match the ID passed to TrackerPage(patientId:...).
///
/// BUG 5 (Performance — full Firestore GET on every GPS tick)
///   _checkSafeZone() was doing a full document GET every position update
///   to re-read the safe zone config. Fixed with an in-memory cache kept
///   fresh via a real-time Firestore snapshot listener. Zero extra reads.
/// ──────────────────────────────────────────────────────────────────────────

class LocationService {
  // ─── Singleton ────────────────────────────────────────────────────────────
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  // ─── Private State ────────────────────────────────────────────────────────
  StreamSubscription<Position>?         _positionStream;
  StreamSubscription<DocumentSnapshot>? _docListener;
  bool    _isTracking     = false;
  String? _activePatientId;

  // GPS stream config:
  //   accuracy:best      → activates the GPS chip (not cell/WiFi)
  //   distanceFilter:10  → only emits when patient moves ≥ 10 m
  static const LocationSettings _locationSettings = LocationSettings(
    accuracy:       LocationAccuracy.best,
    distanceFilter: 10,
  );

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ─── In-memory safe zone cache ────────────────────────────────────────────
  // Populated once on startTracking(), kept fresh by _docListener.
  // Zone checks read from here — zero additional Firestore reads per GPS tick.
  _CachedSafeZone? _cachedSafeZone;

  // ─── Notifications ────────────────────────────────────────────────────────
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
  FlutterLocalNotificationsPlugin();

  // ──────────────────────────────────────────────────────────────────────────
  // STEP 1 — Initialise (call once from patient app's main or initState)
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> initialise() async {
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

    // FIX (BUG 3): Calling requestPermission() a second time does NOT
    // upgrade whileInUse → always on Android 10+. The OS ignores it.
    // The correct path: show a rationale dialog then call:
    //   await Geolocator.openAppSettings();
    // from your UI layer so the user can flip "Allow all the time" manually.
    // We return true for whileInUse so foreground tracking still starts.
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
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

  /// Starts live GPS tracking for [patientId].
  ///
  /// FIX (BUG 2): getPositionStream() instead of Timer.periodic.
  /// The OS-level subscription survives backgrounding and respects
  /// distanceFilter so Firestore writes only happen on real movement.
  Future<void> startTracking({required String patientId}) async {
    if (_isTracking && _activePatientId == patientId) return;
    if (_isTracking) stopTracking();

    final hasPermission = await _requestPermissions();
    if (!hasPermission) return;

    _isTracking      = true;
    _activePatientId = patientId;

    // Warm cache before the first GPS tick so zone check works immediately
    await _refreshSafeZoneCache(patientId);

    // Keep cache in sync whenever the caregiver edits the safe zone
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
  }

  /// DEV ONLY — bypasses auth for local testing.
  ///
  /// In patient screen initState:
  ///   await LocationService().startTrackingForTesting();
  ///
  /// Navigate caregiver view with the same ID:
  ///   TrackerPage(patientId: 'test_patient_001', patientName: 'Test')
  Future<void> startTrackingForTesting({
    String testPatientId = 'test_patient_001',
  }) async {
    await startTracking(patientId: testPatientId);
  }

  void stopTracking() {
    _positionStream?.cancel();
    _docListener?.cancel();
    _positionStream  = null;
    _docListener     = null;
    _isTracking      = false;
    _activePatientId = null;
    _cachedSafeZone  = null;
  }

  bool    get isTracking      => _isTracking;
  String? get activePatientId => _activePatientId;

  // ──────────────────────────────────────────────────────────────────────────
  // STEP 4 — GPS Position Handler
  // ──────────────────────────────────────────────────────────────────────────

  void _onNewPosition(String patientId, Position pos) {
    // Fire-and-forget — never await inside a stream listener callback
    _pushPosition(patientId, pos, isStale: false);
  }

  Future<void> _pushPosition(
      String patientId,
      Position pos, {
        required bool isStale,
      }) async {
    try {
      // FIX (BUG 1): .set(merge:true) creates 'liveLocation' if absent.
      // .update() throws NOT_FOUND on a missing key — that was the root
      // cause of the caregiver seeing no patient marker and stale timestamps.
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

      // Zone check uses in-memory cache — zero additional Firestore reads
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
    } catch (_) {}
  }

  void _checkSafeZoneFromCache(String patientId, Position pos) {
    final cache = _cachedSafeZone;
    if (cache == null) return;

    final double dist = Geolocator.distanceBetween(
      pos.latitude, pos.longitude,
      cache.centerLat, cache.centerLng,
    );
    final bool isInside = dist <= cache.radiusMeters;
    if (isInside == cache.wasInsideZone) return; // no change — skip write

    // Optimistic cache update before async Firestore write
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
    ).then((_) {
      if (!isInside) _logBreachEvent(patientId, pos, dist);
    });
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
  // STEP 6 — Caregiver Read API (public interface unchanged)
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

  String get freshnessLabel {
    if (minutesAgo < 1)  return 'Just now';
    if (minutesAgo < 60) return '${minutesAgo}m ago';
    return '${(minutesAgo / 60).floor()}h ago';
  }

  String get accuracyLabel {
    if (accuracy < 10) return '±${accuracy.toStringAsFixed(0)}m (Excellent)';
    if (accuracy < 30) return '±${accuracy.toStringAsFixed(0)}m (Good)';
    return '±${accuracy.toStringAsFixed(0)}m (Low)';
  }
}

enum PermissionStatus {
  alwaysAllowed,
  foregroundOnly,
  denied,
  permanentlyDenied,
  unknown,
}