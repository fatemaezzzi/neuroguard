import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:neuroguard/core/models/alert_model.dart';
import 'package:neuroguard/core/services/alert_service.dart';
import 'package:geolocator/geolocator.dart';


// GeofenceService — Caregiver Side
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
  bool _wasInsideZone = true;
  bool _notificationsInitialised = false;
  String? _currentPatientId;
  bool _supervisedCooldown = false;
  Timer? _repeatAlertTimer;

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
  FlutterLocalNotificationsPlugin();

  static const int _breachNotificationId = 1001;
  static const String _breachChannelId = 'safezone_breach';
  static const String _breachChannelName = 'Safe Zone Alerts';

  final StreamController<GeofenceEvent> _eventController =
  StreamController<GeofenceEvent>.broadcast();

  Stream<GeofenceEvent> get eventStream => _eventController.stream;

  // ──────────────────────────────────────────────────────────────────────────
  // STEP 1 — Initialise Notifications
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> initialise() async {
    if (_notificationsInitialised) return;   // singleton — run once only
    _notificationsInitialised = true;
    await _setupNotificationChannel();
  }

  Future<void> _setupNotificationChannel() async {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      _breachChannelId,
      _breachChannelName,
      description: 'Alerts when patient leaves the designated safe zone',
      importance: Importance.high,
      enableVibration: true,
      playSound: true,
    );

    final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
    _notificationsPlugin.resolvePlatformSpecificImplementation
    <AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(channel);

    const AndroidInitializationSettings androidSettings =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initSettings =
    InitializationSettings(android: androidSettings);

    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
      onDidReceiveBackgroundNotificationResponse:
      _onBackgroundNotificationResponse,
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // STEP 2 — Start / Stop Watching
  // ──────────────────────────────────────────────────────────────────────────

  void startWatching({required String patientId}) {
    _currentPatientId = patientId;
    _zoneListener?.cancel();
    _zoneListener = _db
        .collection('users')
        .doc(patientId)
        .snapshots()
        .listen((snapshot) => _handleDocumentUpdate(snapshot, patientId));
  }

  void stopWatching() {
    _zoneListener?.cancel();
    _zoneListener = null;
    _currentPatientId = null;
    _wasInsideZone = true;
    _supervisedCooldown = false;
    _repeatAlertTimer?.cancel();
    _repeatAlertTimer = null;
  }

  Future<void> _handleDocumentUpdate(
      DocumentSnapshot snapshot, String patientId) async {
    final data = snapshot.data() as Map<String, dynamic>?;
    if (data == null) return;

    final safeZone = data['safeZone'] as Map<String, dynamic>?;
    if (safeZone == null) return;

    final bool isInsideZone = safeZone['isInsideZone'] ?? true;
    final double distance =
        (safeZone['distanceFromCenter'] as num?)?.toDouble() ?? 0.0;
    final double radius =
        (safeZone['radiusMeters'] as num?)?.toDouble() ?? 300.0;

    // Don't re-fire breach events during a supervised outing window.
    final Timestamp? supervisedUntilTs =
    safeZone['supervisedUntil'] as Timestamp?;
    final bool inSupervisedWindow = supervisedUntilTs != null &&
        supervisedUntilTs.toDate().isAfter(DateTime.now());

    if (_wasInsideZone && !isInsideZone) {
      _wasInsideZone = false;
      _supervisedCooldown = false; // reset for new breach

      if (inSupervisedWindow) return; // caregiver already acknowledged this outing

      // Write breach event — this is what acknowledgeBreachAsSafe queries
      await _db
          .collection('users')
          .doc(patientId)
          .collection('breachEvents')
          .add({
        'timestamp': FieldValue.serverTimestamp(),
        'acknowledged': false,
        'distanceFromCenter': distance,
        'radiusMeters': radius,
      });

      final event = GeofenceEvent(
        patientId: patientId,
        type: GeofenceEventType.exit,
        distanceFromCenter: distance,
        radiusMeters: radius,
        timestamp: DateTime.now(),
      );

      _eventController.add(event);

      // FCM push to caregiver via AlertService
      AlertService().send(
        patientId: patientId,
        alert: AlertModel(
          type: AlertType.geoFence,
          message: 'Patient is outside the safe zone.',
          severity: AlertSeverity.critical,
          metadata: {
            'distanceFromCenter': distance,
            'radiusMeters': radius,
          },
        ),
      );

      _showBreachNotification(event);
    } else if (!_wasInsideZone && isInsideZone) {
      // Patient returned — reset everything
      _wasInsideZone = true;
      _supervisedCooldown = false;
      _repeatAlertTimer?.cancel();
      _repeatAlertTimer = null;

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
  // STEP 3 — Breach Notification
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _showBreachNotification(GeofenceEvent event) async {
    final int distanceMeters = event.distanceFromCenter.round();
    final int outsideBy =
    (event.distanceFromCenter - event.radiusMeters).round();

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
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
        contentTitle: 'Patient Outside Safe Zone',
        summaryText: 'NeuroGuard Alert',
      ),
      actions: <AndroidNotificationAction>[
        const AndroidNotificationAction(
          'action_supervised',
          'It\'s fine, supervised',
          showsUserInterface: false,
          cancelNotification: true,
        ),
        const AndroidNotificationAction(
          'action_not_supervised',
          'Not supervised — Alert',
          showsUserInterface: true,
          cancelNotification: true,
        ),
      ],
    );

    await _notificationsPlugin.show(
      _breachNotificationId,
      'Patient Outside Safe Zone',
      'Patient is ${outsideBy}m outside safe zone. Tap to view location.',
      NotificationDetails(android: androidDetails),
      payload: event.patientId,
    );
  }

  Future<void> _dismissBreachNotification() async {
    await _notificationsPlugin.cancel(_breachNotificationId);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // STEP 4 — Notification Button Handlers
  // ──────────────────────────────────────────────────────────────────────────

  void _onNotificationResponse(NotificationResponse response) {
    final String? patientId = response.payload;
    if (patientId == null) return;

    if (response.actionId == 'action_supervised') {
      acknowledgeBreachAsSafe(patientId);
    } else if (response.actionId == 'action_not_supervised') {
      escalateToRedAlert(patientId);
    }
  }

  @pragma('vm:entry-point')
  static void _onBackgroundNotificationResponse(NotificationResponse response) {
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
  // STEP 5 — Acknowledgement
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> acknowledgeBreachAsSafe(String patientId) async {
    try {
      _supervisedCooldown = true;
      _repeatAlertTimer?.cancel();

      // Mark supervised outing in the user doc so repeat breach events are
      // suppressed while the patient remains outside (30-minute window).
      await _db.collection('users').doc(patientId).set({
        'safeZone': {
          'supervisedUntil': Timestamp.fromDate(
              DateTime.now().add(const Duration(minutes: 30))),
        }
      }, SetOptions(merge: true));

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
          'acknowledgedAs': 'supervised',
          'acknowledgedAt': FieldValue.serverTimestamp(),
        });
      }

      if (_currentPatientId != null) {
        _eventController.add(GeofenceEvent(
          patientId: _currentPatientId!,
          type: GeofenceEventType.acknowledgedSafe,
          distanceFromCenter: 0,
          radiusMeters: 0,
          timestamp: DateTime.now(),
        ));
      }
    } catch (_) {}
  }

  Future<void> escalateToRedAlert(String patientId) async {
    try {
      _repeatAlertTimer?.cancel();

      // set(merge:true) — safe even if activeAlert doesn't exist yet
      await _db.collection('users').doc(patientId).set({
        'activeAlert': {
          'type': 'SAFEZONE_BREACH',
          'severity': 'RED',
          'message': 'Patient is outside safe zone without supervision',
          'triggeredAt': FieldValue.serverTimestamp(),
          'resolved': false,
        }
      }, SetOptions(merge: true));

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
          'acknowledgedAs': 'escalated',
          'acknowledgedAt': FieldValue.serverTimestamp(),
        });
      }

      if (_currentPatientId != null) {
        _eventController.add(GeofenceEvent(
          patientId: _currentPatientId!,
          type: GeofenceEventType.escalatedToRedAlert,
          distanceFromCenter: 0,
          radiusMeters: 0,
          timestamp: DateTime.now(),
        ));
      }

      // Immediate FCM + repeat every 10 minutes
      await _sendEscalationFcm(patientId);
      _repeatAlertTimer = Timer.periodic(
        const Duration(minutes: 10),
            (_) => _sendEscalationFcm(patientId),
      );
    } catch (_) {}
  }

  Future<void> _sendEscalationFcm(String patientId) async {
    await AlertService().send(
      patientId: patientId,
      alert: AlertModel(
        type: AlertType.geoFence,
        message:
        'Patient is unsupervised outside safe zone — open Locate to track them or use Spy Call to check in.',
        severity: AlertSeverity.critical,
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // STEP 6 — Safe Zone CRUD
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> saveSafeZone({
    required String patientId,
    required double centerLat,
    required double centerLng,
    required double radiusMeters,
  }) async {
    double distanceFromCenter = 0.0;
    bool isInsideZone = true;

    try {
      final doc = await _db.collection('users').doc(patientId).get();
      final data = doc.data();
      final loc = data?['liveLocation'] as Map<String, dynamic>?;
      if (loc != null) {
        final patLat = (loc['latitude'] as num).toDouble();
        final patLng = (loc['longitude'] as num).toDouble();
        distanceFromCenter = Geolocator.distanceBetween(
          patLat, patLng, centerLat, centerLng,
        );
        isInsideZone = distanceFromCenter <= radiusMeters;
      }
    } catch (_) {}

    await _db.collection('users').doc(patientId).update({
      'safeZone': {
        'centerLat': centerLat,
        'centerLng': centerLng,
        'radiusMeters': radiusMeters,
        'isInsideZone': isInsideZone,
        'distanceFromCenter': distanceFromCenter,
        'lastUpdated': FieldValue.serverTimestamp(),
      }
    });
  }

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
      distanceFromCenter:
      (sz['distanceFromCenter'] as num?)?.toDouble() ?? 0.0,
    );
  }

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

  static double calculateDistanceMeters({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
  }) {
    return Geolocator.distanceBetween(fromLat, fromLng, toLat, toLng);
  }

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

  double get distanceOutsideZone {
    if (isInsideZone) return 0;
    return (distanceFromCenter - radiusMeters).clamp(0, double.infinity);
  }
}

enum GeofenceEventType {
  exit,
  enter,
  acknowledgedSafe,
  escalatedToRedAlert,
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