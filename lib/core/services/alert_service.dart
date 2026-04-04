import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import '../models/alert_model.dart';

class AlertService {
  static final AlertService _instance = AlertService._();
  factory AlertService() => _instance;
  AlertService._();

  final _db = FirebaseFirestore.instance;

  // FCM V1 endpoint — replace YOUR_PROJECT_ID with: neuroguard-1f865
  static const _fcmUrl =
      'https://fcm.googleapis.com/v1/projects/neuroguard-1f865/messages:send';

  static const _scopes = ['https://www.googleapis.com/auth/firebase.messaging'];

  Future<void> send({
    required String patientId,
    required AlertModel alert,
  }) async {
    // Write to Firestore first (alert log)
    await _db
        .collection('alerts')
        .doc(patientId)
        .collection('entries')
        .add(alert.toMap());

    // Then push FCM to caregiver
    await _sendFcmToCaregiver(patientId: patientId, alert: alert);
  }

  Future<void> _sendFcmToCaregiver({
    required String patientId,
    required AlertModel alert,
  }) async {
    try {
      // 1. Get caregiver FCM token from Firestore
      final patientDoc = await _db.collection('users').doc(patientId).get();
      final patientData = patientDoc.data();
      final caregiverId = patientData != null
          ? patientData['caregiverId'] as String?
          : null;
      if (caregiverId == null) return;

      final caregiverDoc =
      await _db.collection('users').doc(caregiverId).get();
      final caregiverData = caregiverDoc.data();
      final fcmToken = caregiverData != null
          ? caregiverData['fcmToken'] as String?
          : null;
      if (fcmToken == null) return;

      // 2. Load service account JSON from assets
      final jsonStr =
      await rootBundle.loadString('assets/service_account.json');
      final jsonMap = jsonDecode(jsonStr) as Map<String, dynamic>;

      // 3. Get a short-lived OAuth2 access token
      final credentials = ServiceAccountCredentials.fromJson(jsonMap);
      final authClient = await clientViaServiceAccount(
        credentials,
        _scopes,
        baseClient: http.Client(),
      );

      // 4. Send FCM V1 message
      final response = await authClient.post(
        Uri.parse(_fcmUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'message': {
            'token': fcmToken,
            'notification': {
              'title': _titleFor(alert.type),
              'body': alert.message,
            },
            'data': {
              'type': alert.type.name,
              'severity': alert.severity.name,
              'patientId': patientId,
            },
            'android': {
              'priority': alert.severity == AlertSeverity.critical
                  ? 'HIGH'
                  : 'NORMAL',
              'notification': {
                'channel_id': alert.type == AlertType.geoFence
                    ? 'safezone_breach'
                    : 'medicine_reminders',
              },
            },
          },
        }),
      );

      authClient.close();
    } catch (_) {
      // Firestore write already succeeded — don't crash the app
    }
  }

  String _titleFor(AlertType type) {
    switch (type) {
      case AlertType.geoFence:  return 'Patient outside safe zone';
      case AlertType.medicine:  return 'Medicine reminder';
      case AlertType.spyCall:   return 'Remote monitoring triggered';
      case AlertType.matSensor: return 'Bed alert';
    }
  }
}