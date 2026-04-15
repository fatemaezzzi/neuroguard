// lib/core/services/alert_service.dart
// OPTIMISED BUILD — reduced alert latency via OAuth client caching,
// FCM token caching, and parallel FCM + Firestore dispatch.

import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../models/alert_model.dart';

class AlertService {
  static final AlertService _instance = AlertService._();
  factory AlertService() => _instance;
  AlertService._();

  final _db          = FirebaseFirestore.instance;
  static const _uuid = Uuid();

  static const _fcmUrl =
      'https://fcm.googleapis.com/v1/projects/neuroguard-1f865/messages:send';
  static const _scopes =
  ['https://www.googleapis.com/auth/firebase.messaging'];

  // ── OAuth client cache ────────────────────────────────────────────────────
  // Negotiated once per app session. googleapis_auth auto-refreshes the access
  // token before expiry — we never need to rebuild this client.
  AutoRefreshingAuthClient? _cachedAuthClient;

  Future<AutoRefreshingAuthClient> _getAuthClient() async {
    if (_cachedAuthClient != null) return _cachedAuthClient!;
    final jsonStr     = await rootBundle.loadString('assets/service_account.json');
    final jsonMap     = jsonDecode(jsonStr) as Map<String, dynamic>;
    final credentials = ServiceAccountCredentials.fromJson(jsonMap);
    _cachedAuthClient = await clientViaServiceAccount(
      credentials, _scopes, baseClient: http.Client(),
    );
    print('[AlertService] OAuth client created and cached.');
    return _cachedAuthClient!;
  }

  // ── FCM token cache ───────────────────────────────────────────────────────
  // patientId → caregiver FCM token.
  // Eliminates 2 Firestore reads (patient doc + caregiver doc) on every alert
  // after the first call. Call invalidateFcmTokenCache() after re-pairing.
  final Map<String, String> _fcmTokenCache = {};

  Future<String?> _getCaregiverFcmToken(String patientId) async {
    if (_fcmTokenCache.containsKey(patientId)) {
      print('[AlertService] FCM token served from cache.');
      return _fcmTokenCache[patientId];
    }

    final patientDoc  = await _db.collection('users').doc(patientId).get();
    final caregiverId = patientDoc.data()?['paired_caregiver_id'] as String?;
    if (caregiverId == null || caregiverId.isEmpty) {
      print('[AlertService] No paired_caregiver_id — FCM skipped.');
      return null;
    }

    final caregiverDoc = await _db.collection('users').doc(caregiverId).get();
    final fcmToken     = caregiverDoc.data()?['fcmToken'] as String?;
    if (fcmToken == null || fcmToken.isEmpty) {
      print('[AlertService] No fcmToken on caregiver doc — FCM skipped.');
      return null;
    }

    _fcmTokenCache[patientId] = fcmToken;
    print('[AlertService] FCM token fetched and cached for patient $patientId.');
    return fcmToken;
  }

  /// Call this when a caregiver re-pairs or their FCM token rotates,
  /// so the next alert picks up the fresh token from Firestore.
  void invalidateFcmTokenCache(String patientId) {
    _fcmTokenCache.remove(patientId);
    print('[AlertService] FCM token cache invalidated for patient $patientId.');
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// T+0 entry point.
  /// [onEscalationBegin] — caller injects EscalationService().begin here.
  /// AlertService has zero import of EscalationService (no circular dep).
  Future<void> send({
    required String     patientId,
    required AlertModel alert,
    Future<void> Function(String escalationId, AlertModel alert)?
    onEscalationBegin,
  }) async {
    print('[AlertService] send() called — type: ${alert.type}  patient: $patientId');

    final escalationId = alert.escalationId ?? _uuid.v4();
    final alertToLog   = AlertModel(
      type:         alert.type,
      message:      alert.message,
      severity:     alert.severity,
      escalationId: escalationId,
      metadata: {...alert.metadata, 'escalationId': escalationId},
    );

    // T+0 — FCM + Firestore log dispatched IN PARALLEL.
    // The push notification reaches the caregiver without waiting for the
    // Firestore write to complete.
    await Future.wait([
      _sendFcmToCaregiver(patientId: patientId, alert: alertToLog),
      _db
          .collection('alerts')
          .doc(patientId)
          .collection('entries')
          .add(alertToLog.toMap()),
    ]);
    print('[AlertService] FCM + Firestore write dispatched — escalationId: $escalationId');

    // Hand off to escalation chain
    if (onEscalationBegin != null) {
      print('[AlertService] CALLING ESCALATION BEGIN — escalationId: $escalationId');
      await onEscalationBegin(escalationId, alertToLog);
    } else {
      print('[AlertService] WARNING: onEscalationBegin callback is NULL — '
          'escalation chain will NOT start.');
      print('[AlertService] → Make sure you pass the callback when calling send().');
      print('[AlertService] Example:');
      print('[AlertService]   AlertService().send(');
      print('[AlertService]     patientId: id,');
      print('[AlertService]     alert: alert,');
      print('[AlertService]     onEscalationBegin: (eid, a) => EscalationService().begin(');
      print('[AlertService]       patientId: id, alert: a, escalationId: eid,');
      print('[AlertService]     ),');
      print('[AlertService]   );');
    }
  }

  /// FCM-only send — used by EscalationService for tier re-pushes.
  /// No Firestore write, no new escalation chain.
  Future<void> sendFcmOnly({
    required String     patientId,
    required AlertModel alert,
  }) async {
    print('[AlertService] sendFcmOnly() — tier: ${alert.metadata['escalationTier']}');
    await _sendFcmToCaregiver(patientId: patientId, alert: alert);
  }

  // ── FCM ───────────────────────────────────────────────────────────────────

  Future<void> _sendFcmToCaregiver({
    required String     patientId,
    required AlertModel alert,
  }) async {
    try {
      final fcmToken = await _getCaregiverFcmToken(patientId);
      if (fcmToken == null) return;

      final authClient = await _getAuthClient();

      await authClient.post(
        Uri.parse(_fcmUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'message': {
            'token': fcmToken,
            'notification': {
              'title': _titleFor(alert.type),
              'body':  alert.message,
            },
            'data': {
              'type':           alert.type.name,
              'severity':       alert.severity.name,
              'patientId':      patientId,
              'escalationId':   alert.escalationId ?? '',
              'escalationTier':
              (alert.metadata['escalationTier'] as int? ?? 0).toString(),
            },
            'android': {
              'priority': alert.severity == AlertSeverity.critical
                  ? 'HIGH'
                  : 'NORMAL',
              'notification': {
                'channel_id': alert.type == AlertType.geoFence
                    ? 'safezone_breach'
                    : 'medicine_alarm',
              },
            },
          },
        }),
      );
      print('[AlertService] FCM sent successfully.');
    } catch (e) {
      print('[AlertService] FCM send failed: $e');
      // Reset cached auth client so the next call renegotiates cleanly
      // in case the token was revoked or expired unrecoverably.
      _cachedAuthClient = null;
    }
  }

  String _titleFor(AlertType type) {
    switch (type) {
      case AlertType.geoFence:  return 'Patient outside safe zone';
      case AlertType.medicine:  return 'Medicine reminder';
      case AlertType.spyCall:   return 'Spy call suggestion';
      case AlertType.matSensor: return 'Bed alert';
    }
  }
}