// lib/core/services/background_task_handler.dart
//
// CHANGES FROM ORIGINAL:
//   • onDestroy() now calls EscalationService().cancelAll() before tearing
//     down other services, so no orphaned timers fire after the process ends.
//   • No other logic changed — surgical patch only.
//
// Original header preserved below for reference:
// ─────────────────────────────────────────────────────────────────────────────
// KEY FIX: LocationService has `FirebaseFirestore.instance` as a field
// initializer. Field initializers run at object construction time — before
// onStart() and before _ensureFirebase() could be called.
// Solution: initialize lazily inside _startServices().
//
// TICK CADENCE: ForegroundTaskEventAction.repeat(15000) → 15 s per tick.
//               60 ticks × 15 s = 15 minutes.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/cupertino.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:neuroguard/core/services/escalation_service.dart';    // ← NEW
import 'package:neuroguard/core/services/location_history_service.dart';
import 'package:neuroguard/core/services/location_service.dart';
import 'package:neuroguard/core/services/pocket_check_service.dart';
import 'package:neuroguard/firebase_options.dart';

// ─── Shared-prefs key ─────────────────────────────────────────────────────────

const String kPatientIdPrefKey = 'neuroguard_patient_id';

Future<void> savePatientIdForBackground(String patientId) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(kPatientIdPrefKey, patientId);
}

Future<void> clearPatientIdForBackground() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(kPatientIdPrefKey);
}

// ─── Entry point ──────────────────────────────────────────────────────────────

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(BackgroundTaskHandler());
}

// ─── Handler ──────────────────────────────────────────────────────────────────

class BackgroundTaskHandler extends TaskHandler {

  LocationService?        _locationService;
  LocationHistoryService? _historyService;
  PocketCheckService?     _pocketCheckService;

  bool    _trackingStarted   = false;
  String? _activePatientId;

  static const int _captureEveryNTicks = 60;
  int _ticksSinceCapture = 0;

  // ── Lifecycle ────────────────────────────────────────────────────────────

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await _ensureFirebase();

    final prefs     = await SharedPreferences.getInstance();
    final patientId = prefs.getString(kPatientIdPrefKey);

    if (patientId == null || patientId.isEmpty) {
      debugPrint('[BGTask] No patientId in prefs — waiting for login.');
      return;
    }

    await _startServices(patientId);
  }

  @override
  void onRepeatEvent(DateTime timestamp) async {
    if (!_trackingStarted) {
      await _ensureFirebase();
      final prefs     = await SharedPreferences.getInstance();
      final patientId = prefs.getString(kPatientIdPrefKey);
      if (patientId != null && patientId.isNotEmpty) {
        await _startServices(patientId);
      }
      return;
    }

    _ticksSinceCapture++;
    debugPrint(
      '[BGTask] Tick $_ticksSinceCapture/$_captureEveryNTicks (15 min interval)',
    );

    if (_ticksSinceCapture >= _captureEveryNTicks) {
      _ticksSinceCapture = 0;
      await _captureAndSync();
    }
  }

  @override
  void onReceiveData(Object data) async {
    if (data is Map<String, dynamic> && data.containsKey('patientId')) {
      final patientId = data['patientId'] as String;
      if (_trackingStarted) return;
      await _ensureFirebase();
      await _startServices(patientId);
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    // cancelAll() now calls a Cloud Function — must be awaited
    await EscalationService().cancelAll();

    _locationService?.stopTracking();
    _pocketCheckService?.dispose();
    await _historyService?.dispose();
    _trackingStarted    = false;
    _activePatientId    = null;
    _locationService    = null;
    _historyService     = null;
    _pocketCheckService = null;
    debugPrint('[BGTask] Service destroyed.');
  }


  @override
  void onNotificationButtonPressed(String id) {}

  @override
  void onNotificationPressed() => FlutterForegroundTask.launchApp('/');

  @override
  void onNotificationDismissed() {}

  // ── Private helpers ───────────────────────────────────────────────────────

  Future<void> _ensureFirebase() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      debugPrint('[BGTask] Firebase initialized in background isolate ✅');
    }
  }

  Future<void> _startServices(String patientId) async {
    _activePatientId = patientId;

    _locationService ??= LocationService();
    _historyService  ??= LocationHistoryService();

    await _locationService!.startTracking(patientId: patientId);

    _pocketCheckService = PocketCheckService(patientId: patientId);
    _pocketCheckService!.initialize();

    _trackingStarted = true;

    await _captureAndSync();
    _ticksSinceCapture = 0;

    debugPrint('[BGTask] All services started for $patientId ✅');
  }

  Future<void> _captureAndSync() async {
    if (_activePatientId == null || _historyService == null) return;
    final patientId = _activePatientId!;

    debugPrint('[BGTask] ▶ captureAndSave() for $patientId');
    await _historyService!.captureAndSave(patientId);

    debugPrint('[BGTask] ▶ syncNow() for $patientId');
    await _historyService!.syncNow(patientId);

    debugPrint('[BGTask] ✅ Capture + sync complete for $patientId');
  }
}