// lib/core/services/background_task_handler.dart
//
// BackgroundTaskHandler — Foreground Service Isolate
// ─────────────────────────────────────────────────────────────────────────────
//
// KEY FIX (was crashing before onStart even ran):
//   LocationService has `FirebaseFirestore.instance` as a field initializer.
//   Field initializers run at object construction time — before onStart() and
//   before _ensureFirebase() could be called. So the crash happened the moment
//   `new BackgroundTaskHandler()` was evaluated in startCallback().
//
//   Solution: DO NOT declare LocationService as a field. Instead, initialize
//   it lazily inside _startServices(), which is only called after Firebase is
//   confirmed ready via _ensureFirebase().
//
// TICK CADENCE
//   ForegroundTaskEventAction.repeat(15000) → onRepeatEvent every 15 s.
//   60 ticks × 15 s = 15 minutes
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/cupertino.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  // BackgroundTaskHandler must have NO field initializers that touch Firebase.
  // Firebase is initialized inside onStart() before anything else runs.
  FlutterForegroundTask.setTaskHandler(BackgroundTaskHandler());
}

// ─── Handler ──────────────────────────────────────────────────────────────────

class BackgroundTaskHandler extends TaskHandler {

  // ── LAZY — assigned only after _ensureFirebase() succeeds ─────────────────
  // Do NOT move these back to eager field initializers — that was the crash.
  // LocationService constructor calls FirebaseFirestore.instance immediately,
  // which throws if Firebase hasn't been initialized in this isolate yet.
  LocationService?        _locationService;
  LocationHistoryService? _historyService;
  PocketCheckService?     _pocketCheckService;

  bool    _trackingStarted   = false;
  String? _activePatientId;

  // Tick counter: onRepeatEvent fires every 15 s
  // 60 ticks × 15 s = 15 minutes
  static const int _captureEveryNTicks = 60;
  int _ticksSinceCapture = 0;

  // ── Lifecycle ────────────────────────────────────────────────────────────

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // Firebase MUST be initialized before any service is instantiated.
    await _ensureFirebase();

    final prefs = await SharedPreferences.getInstance();
    final patientId = prefs.getString(kPatientIdPrefKey);

    if (patientId == null || patientId.isEmpty) {
      debugPrint('[BGTask] No patientId in prefs — waiting for login.');
      return;
    }

    await _startServices(patientId);
  }

  @override
  void onRepeatEvent(DateTime timestamp) async {
    // ── Retry: not started yet (login hadn't happened at onStart) ──────────
    if (!_trackingStarted) {
      await _ensureFirebase();
      final prefs = await SharedPreferences.getInstance();
      final patientId = prefs.getString(kPatientIdPrefKey);
      if (patientId != null && patientId.isNotEmpty) {
        await _startServices(patientId);
      }
      return;
    }

    // ── Normal: count ticks and capture+sync at threshold ──────────────────
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

    // Safe to instantiate now — Firebase is guaranteed ready.
    _locationService ??= LocationService();
    _historyService  ??= LocationHistoryService();

    // Real-time live location → Firestore (for the tracker map)
    await _locationService!.startTracking(patientId: patientId);

    // Firestore listener for caregiver-triggered pocket check
    _pocketCheckService = PocketCheckService(patientId: patientId);
    _pocketCheckService!.initialize();

    _trackingStarted = true;

    // Capture + sync immediately on start — don't wait for first tick
    await _captureAndSync();
    _ticksSinceCapture = 0;

    debugPrint('[BGTask] All services started for $patientId ✅');
  }

  /// The full pipeline: GPS fix → SQLite (synced=0) → Firestore (synced=1).
  /// This is what makes data appear in the caregiver's History page.
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