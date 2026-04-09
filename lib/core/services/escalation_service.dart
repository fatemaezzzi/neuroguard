// lib/core/services/escalation_service.dart
//
// ARCHITECTURE CHANGE: All timer logic moved to Cloud Functions.
// This class is now a thin client — it calls createEscalation and
// acknowledgeAlert Cloud Functions. No Dart timers, no API keys, no
// phone numbers. Everything sensitive stays on the server.
//
// Dart-side responsibility:
//   begin()             → calls createEscalation Cloud Function
//   cancel()            → calls acknowledgeAlert Cloud Function
//   cancelAll()         → calls acknowledgeAlert for all active chains

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import '../models/alert_model.dart';

class EscalationService {
  static final EscalationService _instance = EscalationService._();
  factory EscalationService() => _instance;
  EscalationService._();

  final _functions = FirebaseFunctions.instance;

  // Track active escalationIds so cancelAll() can acknowledge them all
  final Set<String> _activeIds = {};

  // ── Public API ────────────────────────────────────────────────────────────

  /// Called by AlertService after T+0 Firestore write + FCM.
  /// Creates an escalation document — Cloud Functions handle the rest.
  Future<void> begin({
    required String     patientId,
    required AlertModel alert,
    required String     escalationId,
  }) async {
    debugPrint('[Escalation] begin() → calling createEscalation Cloud Function');
    debugPrint('[Escalation] escalationId: $escalationId');
    debugPrint('[Escalation] patientId   : $patientId');

    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-south1')
          .httpsCallable('createEscalation');
      final result   = await callable.call({
        'patientId':    patientId,
        'alertType':    alert.type.name,
        'message':      alert.message,
        'severity':     alert.severity.name,
        'escalationId': escalationId,
      });

      _activeIds.add(escalationId);
      debugPrint('[Escalation] Cloud Function response: ${result.data}');
    } catch (e) {
      debugPrint('[Escalation] ERROR calling createEscalation: $e');
    }
  }

  /// Call when caregiver acknowledges the alert — stops further escalation tiers.
  Future<void> cancel(String escalationId) async {
    debugPrint('[Escalation] cancel() → acknowledgeAlert: $escalationId');
    _activeIds.remove(escalationId);
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-south1')
          .httpsCallable('acknowledgeAlert');
      await callable.call({'escalationId': escalationId});
      debugPrint('[Escalation] Acknowledged: $escalationId');
    } catch (e) {
      debugPrint('[Escalation] ERROR acknowledging $escalationId: $e');
    }
  }

  /// Cancel all active escalations — called from BackgroundTaskHandler.onDestroy().
  Future<void> cancelAll() async {
    debugPrint('[Escalation] cancelAll() — ${_activeIds.length} active chain(s)');
    final ids = Set<String>.from(_activeIds);
    for (final id in ids) {
      await cancel(id);
    }
    _activeIds.clear();
  }

  /// Stream the status of a specific escalation — use this to drive the
  /// caregiver UI (show which tier has been reached, whether it's acknowledged).
  Stream<EscalationStatus?> streamStatus(String escalationId) {
    return FirebaseFirestore.instance
        .collection('escalations')
        .doc(escalationId)
        .snapshots()
        .map((snap) {
      if (!snap.exists) return null;
      return EscalationStatus.fromMap(snap.data()!);
    });
  }
}

// ── Status model (for caregiver UI) ──────────────────────────────────────────

class EscalationStatus {
  final String  patientId;
  final String  alertType;
  final String  status;          // 'active' | 'acknowledged' | 'completed'
  final bool    tier1Sent;
  final bool    tier2Sent;
  final bool    tier3Sent;
  final bool    acknowledged;

  const EscalationStatus({
    required this.patientId,
    required this.alertType,
    required this.status,
    required this.tier1Sent,
    required this.tier2Sent,
    required this.tier3Sent,
    required this.acknowledged,
  });

  factory EscalationStatus.fromMap(Map<String, dynamic> m) => EscalationStatus(
    patientId:    (m['patientId']    as String?) ?? '',
    alertType:    (m['alertType']    as String?) ?? '',
    status:       (m['status']       as String?) ?? 'active',
    tier1Sent:    m['tier1SentAt']   != null,
    tier2Sent:    m['tier2SentAt']   != null,
    tier3Sent:    m['tier3SentAt']   != null,
    acknowledged: m['acknowledgedAt'] != null,
  );
}