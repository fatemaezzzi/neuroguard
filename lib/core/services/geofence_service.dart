import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';

/// GeofenceService — Caregiver Side
/// Responsibilities:
///   1. Listen to Firestore for safe zone status changes in real-time.
///   2. When isInsideZone flips to false, fire a local notification.
///   3. Notification has TWO action buttons:
///        "It's fine" — supervised outing, dismiss alert
///        "Not supervised" — escalate to red alert in the app
///   4. Save caregiver's acknowledgement back to Firestore.
///   5. Provide helper methods to save/load safe zone settings.

class GeofenceService {
  // ─── Singleton ────────────────────────────────────────────────────────────
  static final GeofenceService _instance = GeofenceService._internal();
  factory GeofenceService() => _instance;
  GeofenceService._internal();

  // ─── State ────────────────────────────────────────────────────────────────
  StreamSubscription<DocumentSnapshot>? _zoneListener;
  bool _wasInsideZone = true; // Track previous state to detect transitions
  String? _currentPatientId;

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Notification plugin
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
  FlutterLocalNotificationsPlugin();

  // Notification IDs
  static const int _breachNotificationId = 1001;
  static const String _breachChannelId = 'safezone_breach';
  static const String _breachChannelName = 'Safe Zone Alerts';

  // Stream controller so the UI can react to breach events
  final StreamController<GeofenceEvent> _eventController =
  StreamController<GeofenceEvent>.broadcast();

  Stream<GeofenceEvent> get eventStream => _eventController.stream;

  // ──────────────────────────────────────────────────────────────────────────
  // STEP 1 — Initialise Notifications
  // ──────────────────────────────────────────────────────────────────────────

  /// Call once from caregiver app startup (e.g. in main.dart or after login).
  Future<void> initialise() async {
    await _setupNotificationChannel();
  }

  Future<void> _setupNotificationChannel() async {
    // Android notification channel with high importance for alerts
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      _breachChannelId,
      _breachChannelName,
      description: 'Alerts when patient leaves the designated safe zone',
      importance: Importance.high,
      enableVibration: true,
      playSound: true,
    );

    final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
    _notificationsPlugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(channel);

    // Initialise the plugin
    const AndroidInitializationSettings androidSettings =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initSettings =
    InitializationSettings(android: androidSettings);

    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: _onBackgroundNotificationResponse,
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // STEP 2 — Start Listening for Breaches
  // ──────────────────────────────────────────────────────────────────────────

  /// Start watching the patient's safe zone status.
  /// Call this after caregiver logs in.
  void startWatching({required String patientId}) {
    _currentPatientId = patientId;

    // Cancel any previous listener before starting a new one
    _zoneListener?.cancel();

    _zoneListener = _db
        .collection('users')
        .doc(patientId)
        .snapshots()
        .listen((DocumentSnapshot snapshot) {
      _handleDocumentUpdate(snapshot, patientId);
    });
  }

  /// Stop watching. Call on logout.
  void stopWatching() {
    _zoneListener?.cancel();
    _zoneListener = null;
    _currentPatientId = null;
    _wasInsideZone = true;
  }

  void _handleDocumentUpdate(DocumentSnapshot snapshot, String patientId) {
    final data = snapshot.data() as Map<String, dynamic>?;
    if (data == null) return;

    final safeZone = data['safeZone'] as Map<String, dynamic>?;
    if (safeZone == null) return;

    final bool isInsideZone = safeZone['isInsideZone'] ?? true;
    final double distance =
        (safeZone['distanceFromCenter'] as num?)?.toDouble() ?? 0.0;
    final double radius =
        (safeZone['radiusMeters'] as num?)?.toDouble() ?? 300.0;

    // Only react on TRANSITION: inside → outside
    // This prevents repeated notifications while patient is already outside
    if (_wasInsideZone && !isInsideZone) {
      _wasInsideZone = false;

      final event = GeofenceEvent(
        patientId: patientId,
        type: GeofenceEventType.exit,
        distanceFromCenter: distance,
        radiusMeters: radius,
        timestamp: DateTime.now(),
      );

      // Emit to UI stream (so TrackerPage can show alert overlay)
      _eventController.add(event);

      // Fire local notification with action buttons
      _showBreachNotification(event);
    } else if (!_wasInsideZone && isInsideZone) {
      // Patient returned to safe zone — resolve the alert
      _wasInsideZone = true;

      final event = GeofenceEvent(
        patientId: patientId,
        type: GeofenceEventType.enter,
        distanceFromCenter: distance,
        radiusMeters: radius,
        timestamp: DateTime.now(),
      );

      _eventController.add(event);
      _dismissBreachNotification();
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // STEP 3 — Breach Notification with Action Buttons
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _showBreachNotification(GeofenceEvent event) async {
    final int distanceMeters = event.distanceFromCenter.round();
    final int outsideBy = (event.distanceFromCenter - event.radiusMeters).round();

    // Two action buttons on the notification:
    //   Action 0 → "It's Fine" (supervised, dismiss)
    //   Action 1 → "Not Supervised" (escalate to red alert)
    final AndroidNotificationDetails androidDetails =
    AndroidNotificationDetails(
      _breachChannelId,
      _breachChannelName,
      channelDescription: 'Patient safe zone alerts',
      importance: Importance.high,
      priority: Priority.high,
      ticker: 'Safe Zone Alert',
      styleInformation: BigTextStyleInformation(
        'Patient is approximately ${outsideBy}m outside their safe zone.\n'
            'Total distance from home: ${distanceMeters}m\n\n'
            'Is this a supervised outing?',
        contentTitle: '⚠️ Patient Outside Safe Zone',
        summaryText: 'NeuroGuard Alert',
      ),
      actions: <AndroidNotificationAction>[
        const AndroidNotificationAction(
          'action_supervised',           // Action ID
          '✅  It\'s fine, supervised',  // Button label
          showsUserInterface: false,     // Dismiss without opening app
          cancelNotification: true,
        ),
        const AndroidNotificationAction(
          'action_not_supervised',       // Action ID
          '🚨  Not supervised — Alert',  // Button label
          showsUserInterface: true,      // Opens the app to tracker page
          cancelNotification: true,
        ),
      ],
    );

    final NotificationDetails notificationDetails =
    NotificationDetails(android: androidDetails);

    await _notificationsPlugin.show(
      _breachNotificationId,
      '⚠️ Patient Outside Safe Zone',
      'Patient is ${outsideBy}m outside safe zone. Tap to view location.',
      notificationDetails,
      payload: event.patientId, // Pass patientId so we can open the right patient
    );
  }

  Future<void> _dismissBreachNotification() async {
    await _notificationsPlugin.cancel(_breachNotificationId);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // STEP 4 — Handle Notification Action Button Taps
  // ──────────────────────────────────────────────────────────────────────────

  void _onNotificationResponse(NotificationResponse response) {
    final String? patientId = response.payload;
    if (patientId == null) return;

    if (response.actionId == 'action_supervised') {
      // Caregiver says it's fine — mark as acknowledged, no escalation
      acknowledgeBreachAsSafe(patientId);
    } else if (response.actionId == 'action_not_supervised') {
      // Caregiver says NOT supervised — escalate to red alert in app
      escalateToRedAlert(patientId);
    }
  }

  @pragma('vm:entry-point')
  static void _onBackgroundNotificationResponse(NotificationResponse response) {
    // Background handler — must be a top-level or static function
    // For full background handling, use flutter_background_service
    final String? patientId = response.payload;
    if (patientId == null) return;

    if (response.actionId == 'action_supervised') {
      FirebaseFirestore.instance
          .collection('users')
          .doc(patientId)
          .collection('breachEvents')
          .where('acknowledged', isEqualTo: false)
          .limit(1)
          .get()
          .then((query) {
        for (final doc in query.docs) {
          doc.reference.update({
            'acknowledged': true,
            'acknowledgedAs': 'supervised',
            'acknowledgedAt': FieldValue.serverTimestamp(),
          });
        }
      });
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // STEP 5 — Acknowledgement Helpers
  // ──────────────────────────────────────────────────────────────────────────

  /// Marks the latest breach as acknowledged (supervised outing).
  Future<void> acknowledgeBreachAsSafe(String patientId) async {
    try {
      final query = await _db
          .collection('users')
          .doc(patientId)
          .collection('breachEvents')
          .where('acknowledged', isEqualTo: false)
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();

      for (final doc in query.docs) {
        await doc.reference.update({
          'acknowledged': true,
          'acknowledgedAs': 'supervised',  // "It's fine"
          'acknowledgedAt': FieldValue.serverTimestamp(),
        });
      }

      // Emit resolved event to UI
      if (_currentPatientId != null) {
        _eventController.add(GeofenceEvent(
          patientId: _currentPatientId!,
          type: GeofenceEventType.acknowledgedSafe,
          distanceFromCenter: 0,
          radiusMeters: 0,
          timestamp: DateTime.now(),
        ));
      }
    } catch (e) {
      // Log error in production
    }
  }

  /// Escalates the breach — sets a red alert flag the UI watches.
  Future<void> escalateToRedAlert(String patientId) async {
    try {
      // Update the patient document with an active red alert
      await _db.collection('users').doc(patientId).update({
        'activeAlert': {
          'type': 'SAFEZONE_BREACH',
          'severity': 'RED',
          'message': 'Patient is outside safe zone without supervision',
          'triggeredAt': FieldValue.serverTimestamp(),
          'resolved': false,
        }
      });

      // Mark breach event as escalated
      final query = await _db
          .collection('users')
          .doc(patientId)
          .collection('breachEvents')
          .where('acknowledged', isEqualTo: false)
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();

      for (final doc in query.docs) {
        await doc.reference.update({
          'acknowledged': true,
          'acknowledgedAs': 'escalated', // "Not supervised"
          'acknowledgedAt': FieldValue.serverTimestamp(),
        });
      }

      // Emit red alert event to UI
      if (_currentPatientId != null) {
        _eventController.add(GeofenceEvent(
          patientId: _currentPatientId!,
          type: GeofenceEventType.escalatedToRedAlert,
          distanceFromCenter: 0,
          radiusMeters: 0,
          timestamp: DateTime.now(),
        ));
      }
    } catch (e) {
      // Log error in production
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // STEP 6 — Safe Zone CRUD (Caregiver sets/edits safe zone)
  // ──────────────────────────────────────────────────────────────────────────

  /// Save a new safe zone to Firestore.
  /// Call from [SafeZoneEditorPage] when caregiver taps "Save".
  Future<void> saveSafeZone({
    required String patientId,
    required double centerLat,
    required double centerLng,
    required double radiusMeters,
  }) async {
    await _db.collection('users').doc(patientId).update({
      'safeZone': {
        'centerLat': centerLat,
        'centerLng': centerLng,
        'radiusMeters': radiusMeters,
        'isInsideZone': true,        // Assume inside when zone is first set
        'distanceFromCenter': 0.0,
        'lastUpdated': FieldValue.serverTimestamp(),
      }
    });
  }

  /// Load the current safe zone for a patient.
  /// Returns null if no safe zone has been set yet.
  Future<SafeZoneModel?> getSafeZone(String patientId) async {
    final doc = await _db.collection('users').doc(patientId).get();
    final data = doc.data();
    if (data == null || data['safeZone'] == null) return null;

    final sz = data['safeZone'] as Map<String, dynamic>;
    return SafeZoneModel(
      centerLat: (sz['centerLat'] as num).toDouble(),
      centerLng: (sz['centerLng'] as num).toDouble(),
      radiusMeters: (sz['radiusMeters'] as num).toDouble(),
      isInsideZone: sz['isInsideZone'] ?? true,
      distanceFromCenter: (sz['distanceFromCenter'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// Stream safe zone data in real-time (used by TrackerPage map)
  Stream<SafeZoneModel?> streamSafeZone(String patientId) {
    return _db.collection('users').doc(patientId).snapshots().map((doc) {
      final data = doc.data();
      if (data == null || data['safeZone'] == null) return null;

      final sz = data['safeZone'] as Map<String, dynamic>;
      return SafeZoneModel(
        centerLat: (sz['centerLat'] as num).toDouble(),
        centerLng: (sz['centerLng'] as num).toDouble(),
        radiusMeters: (sz['radiusMeters'] as num).toDouble(),
        isInsideZone: sz['isInsideZone'] ?? true,
        distanceFromCenter:
        (sz['distanceFromCenter'] as num?)?.toDouble() ?? 0.0,
      );
    });
  }

  // ──────────────────────────────────────────────────────────────────────────
  // STEP 7 — Distance Utility
  // ──────────────────────────────────────────────────────────────────────────

  /// Pure utility — calculates distance between two GPS points.
  /// Returns distance in metres.
  static double calculateDistanceMeters({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
  }) {
    return Geolocator.distanceBetween(fromLat, fromLng, toLat, toLng);
  }

  /// Returns a human-readable distance string
  static String formatDistance(double meters) {
    if (meters < 1000) return '${meters.toStringAsFixed(0)}m';
    return '${(meters / 1000).toStringAsFixed(1)}km';
  }

  void dispose() {
    stopWatching();
    _eventController.close();
  }
}

// ─── Data Models ─────────────────────────────────────────────────────────────

class SafeZoneModel {
  final double centerLat;
  final double centerLng;
  final double radiusMeters;
  final bool isInsideZone;
  final double distanceFromCenter;

  const SafeZoneModel({
    required this.centerLat,
    required this.centerLng,
    required this.radiusMeters,
    required this.isInsideZone,
    required this.distanceFromCenter,
  });

  /// How far outside the zone the patient is (0 if inside)
  double get distanceOutsideZone {
    if (isInsideZone) return 0;
    return (distanceFromCenter - radiusMeters).clamp(0, double.infinity);
  }
}

enum GeofenceEventType {
  exit,                // Patient left safe zone
  enter,               // Patient returned to safe zone
  acknowledgedSafe,    // Caregiver said "it's fine"
  escalatedToRedAlert, // Caregiver said "not supervised"
}

class GeofenceEvent {
  final String patientId;
  final GeofenceEventType type;
  final double distanceFromCenter;
  final double radiusMeters;
  final DateTime timestamp;

  const GeofenceEvent({
    required this.patientId,
    required this.type,
    required this.distanceFromCenter,
    required this.radiusMeters,
    required this.timestamp,
  });

  bool get isExitEvent => type == GeofenceEventType.exit;
  bool get isEnterEvent => type == GeofenceEventType.enter;
  bool get isEscalated => type == GeofenceEventType.escalatedToRedAlert;
}