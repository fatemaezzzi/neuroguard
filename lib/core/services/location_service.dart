import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// LocationService — Patient Side
/// Runs on the PATIENT's phone.
/// Responsibilities:
///   1. Request and validate GPS permissions (including background).
///   2. Start a periodic timer that fetches high-accuracy GPS coordinates.
///   3. Push each coordinate update to Firebase Firestore.
///   4. Compare current position against the stored safe zone.
///   5. Update isInsideZone flag so the caregiver app reacts in real-time.

class LocationService {
  // ─── Singleton ────────────────────────────────────────────────────────────
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  // ─── Private State ────────────────────────────────────────────────────────
  Timer? _trackingTimer;
  StreamSubscription<Position>? _positionStream;
  bool _isTracking = false;

  // How often we push location to Firebase (in seconds).
  // 30s = good balance of battery vs freshness for a dementia patient.
  static const int _updateIntervalSeconds = 30;

  // Firestore reference
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ─── Notifications (for breach alerts on patient phone) ───────────────────
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
  FlutterLocalNotificationsPlugin();

  // ──────────────────────────────────────────────────────────────────────────
  // STEP 1 — Initialise (call once from patient app's main or initState)
  // ──────────────────────────────────────────────────────────────────────────

  /// Call this once when the patient app starts.
  /// Sets up notification channel and requests all required permissions.
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
  // STEP 2 — Permission Handling
  // ──────────────────────────────────────────────────────────────────────────

  /// Requests foreground + background location permissions.
  /// Returns true if all permissions are granted, false otherwise.
  Future<bool> _requestPermissions() async {
    // Check if location services are enabled on the device at all
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Location services are disabled — cannot proceed
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();

    // If permission was denied before, ask again
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    // If permanently denied, we cannot request again — user must go to settings
    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    // On Android 10+, we need explicit "Allow all the time" (background) permission
    // This is handled separately from foreground permission
    if (permission == LocationPermission.whileInUse) {
      // Note: On Android, you must request background permission AFTER
      // foreground is granted. The system will show a separate dialog.
      permission = await Geolocator.requestPermission();
    }

    return permission == LocationPermission.always;
  }

  /// Public method so UI can check and prompt user if needed
  Future<PermissionStatus> getPermissionStatus() async {
    final permission = await Geolocator.checkPermission();
    switch (permission) {
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

  /// Starts periodic GPS tracking for the given [patientId].
  /// Call from the patient app after authentication.
  Future<void> startTracking({required String patientId}) async {
    if (_isTracking) return; // Already running

    final hasPermission = await _requestPermissions();
    if (!hasPermission) {
      // You could emit an error state here for the UI to show a dialog
      return;
    }

    _isTracking = true;

    // Do an immediate first push so the caregiver sees location right away
    await _pushLocationToFirebase(patientId);

    // Then push every [_updateIntervalSeconds] seconds
    _trackingTimer = Timer.periodic(
      Duration(seconds: _updateIntervalSeconds),
          (_) async {
        await _pushLocationToFirebase(patientId);
      },
    );
  }

  /// Stops periodic tracking. Call on logout or app close.
  void stopTracking() {
    _trackingTimer?.cancel();
    _positionStream?.cancel();
    _trackingTimer = null;
    _positionStream = null;
    _isTracking = false;
  }

  bool get isTracking => _isTracking;

  // ──────────────────────────────────────────────────────────────────────────
  // STEP 4 — Fetch GPS and Push to Firebase
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _pushLocationToFirebase(String patientId) async {
    try {
      // LocationAccuracy.best forces the GPS chip to activate
      // (rather than relying on cell towers / WiFi — less accurate)
      final Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 10),
      );

      // Push live location to Firestore
      await _db.collection('users').doc(patientId).update({
        'liveLocation.latitude': position.latitude,
        'liveLocation.longitude': position.longitude,
        'liveLocation.accuracy': position.accuracy,
        'liveLocation.timestamp': FieldValue.serverTimestamp(),
        'liveLocation.speed': position.speed, // m/s — useful for gait analysis
        'liveLocation.heading': position.heading,
      });

      // After pushing location, check if patient is still inside safe zone
      await _checkSafeZone(patientId, position);
    } catch (e) {
      // If location fetch times out (e.g. patient is indoors), push last known
      final Position? lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        await _db.collection('users').doc(patientId).update({
          'liveLocation.latitude': lastKnown.latitude,
          'liveLocation.longitude': lastKnown.longitude,
          'liveLocation.accuracy': lastKnown.accuracy,
          'liveLocation.timestamp': FieldValue.serverTimestamp(),
          'liveLocation.isStale': true, // Flag that this is old data
        });
      }
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // STEP 5 — Safe Zone Check
  // ──────────────────────────────────────────────────────────────────────────

  /// Reads the safe zone from Firestore and checks if the patient is inside it.
  /// Updates the isInsideZone field which the caregiver app listens to.
  Future<void> _checkSafeZone(String patientId, Position currentPosition) async {
    try {
      final doc = await _db.collection('users').doc(patientId).get();
      final data = doc.data();

      if (data == null || data['safeZone'] == null) return;

      final safeZone = data['safeZone'] as Map<String, dynamic>;
      final double zoneLat = safeZone['centerLat'];
      final double zoneLng = safeZone['centerLng'];
      final double radiusMeters = (safeZone['radiusMeters'] as num).toDouble();

      // Calculate straight-line distance between patient and zone center
      final double distanceMeters = Geolocator.distanceBetween(
        currentPosition.latitude,
        currentPosition.longitude,
        zoneLat,
        zoneLng,
      );

      final bool isInsideZone = distanceMeters <= radiusMeters;
      final bool wasInsideZone = safeZone['isInsideZone'] ?? true;

      // Only update Firestore if status changed (avoid unnecessary writes)
      if (isInsideZone != wasInsideZone) {
        await _db.collection('users').doc(patientId).update({
          'safeZone.isInsideZone': isInsideZone,
          'safeZone.lastBreachTime':
          isInsideZone ? null : FieldValue.serverTimestamp(),
          'safeZone.distanceFromCenter': distanceMeters,
        });

        // If patient just left the zone, log a breach event for history
        if (!isInsideZone) {
          await _db
              .collection('users')
              .doc(patientId)
              .collection('breachEvents')
              .add({
            'latitude': currentPosition.latitude,
            'longitude': currentPosition.longitude,
            'distanceFromCenter': distanceMeters,
            'timestamp': FieldValue.serverTimestamp(),
            'acknowledged': false, // Caregiver hasn't responded yet
          });
        }
      }
    } catch (e) {
      // Silently fail — location still pushed, zone check is secondary
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // STEP 6 — One-time Location Fetch (for caregiver "LOCATE" button)
  // ──────────────────────────────────────────────────────────────────────────

  /// Fetches the patient's current location from Firestore.
  /// Used by the caregiver app — does NOT require GPS permission on caregiver's phone.
  static Future<LocationSnapshot?> getPatientLocation(String patientId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(patientId)
          .get();

      final data = doc.data();
      if (data == null || data['liveLocation'] == null) return null;

      final loc = data['liveLocation'] as Map<String, dynamic>;
      return LocationSnapshot(
        latitude: (loc['latitude'] as num).toDouble(),
        longitude: (loc['longitude'] as num).toDouble(),
        accuracy: (loc['accuracy'] as num?)?.toDouble() ?? 0.0,
        timestamp: (loc['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
        isStale: loc['isStale'] ?? false,
        speed: (loc['speed'] as num?)?.toDouble() ?? 0.0,
      );
    } catch (e) {
      return null;
    }
  }

  /// Returns a real-time stream of the patient's location.
  /// The caregiver map widget listens to this to auto-update the marker.
  static Stream<LocationSnapshot?> streamPatientLocation(String patientId) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(patientId)
        .snapshots()
        .map((doc) {
      final data = doc.data();
      if (data == null || data['liveLocation'] == null) return null;

      final loc = data['liveLocation'] as Map<String, dynamic>;
      return LocationSnapshot(
        latitude: (loc['latitude'] as num).toDouble(),
        longitude: (loc['longitude'] as num).toDouble(),
        accuracy: (loc['accuracy'] as num?)?.toDouble() ?? 0.0,
        timestamp: (loc['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
        isStale: loc['isStale'] ?? false,
        speed: (loc['speed'] as num?)?.toDouble() ?? 0.0,
      );
    });
  }
}

// ─── Supporting Data Classes ─────────────────────────────────────────────────

/// Snapshot of a patient's location at a point in time.
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

  /// Returns how many minutes ago this location was recorded
  int get minutesAgo => DateTime.now().difference(timestamp).inMinutes;

  String get freshnessLabel {
    if (minutesAgo < 1) return 'Just now';
    if (minutesAgo < 60) return '${minutesAgo}m ago';
    return '${(minutesAgo / 60).floor()}h ago';
  }

  String get accuracyLabel {
    if (accuracy < 10) return '±${accuracy.toStringAsFixed(0)}m (Excellent)';
    if (accuracy < 30) return '±${accuracy.toStringAsFixed(0)}m (Good)';
    return '±${accuracy.toStringAsFixed(0)}m (Low)';
  }
}

/// Permission status abstraction to decouple UI from geolocator internals
enum PermissionStatus {
  alwaysAllowed,
  foregroundOnly,
  denied,
  permanentlyDenied,
  unknown,
}