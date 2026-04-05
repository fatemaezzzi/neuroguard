// lib/core/services/background_task_handler.dart
//
// BackgroundTaskHandler — Foreground Service Isolate
// ─────────────────────────────────────────────────────────────────────────────
//
// This runs in a SEPARATE Dart isolate from the UI. It owns the full
// capture → SQLite → Firestore sync pipeline. The main isolate does NOT
// run any Timer.periodic for location history — this handler is the sole owner.
//
// TICK CADENCE
//   ForegroundTaskEventAction.repeat(15000) fires onRepeatEvent every 15 s.
//   We count ticks and capture+sync at the configured threshold:
//     Debug build  → 4 ticks  = 1 minute   (easy to verify in logs)
//     Release build → 60 ticks = 15 minutes (production cadence)
//
// FLOW PER CAPTURE TICK
//   1. captureAndSave()  — GPS fix → SQLite (synced = 0)
//   2. syncNow()         — SQLite rows with synced=0 → Firestore batch write
//                          → marks rows synced=1 in SQLite
//   The caregiver's LocationHistoryPage reads Firestore and will now see data.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:neuroguard/core/services/location_service.dart';
import 'package:neuroguard/core/services/location_history_service.dart';
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
  final LocationService _locationService = LocationService();

  // Each isolate gets its own instance — this is correct and intentional.
  // The background isolate is the ONLY place that calls captureAndSave/syncNow.
  final LocationHistoryService _historyService = LocationHistoryService();

  PocketCheckService? _pocketCheckService;
  bool    _trackingStarted = false;
  String? _activePatientId;

  // ── Tick counter for location-history cadence ─────────────────────────────
  //
  // onRepeatEvent fires every 15 seconds.
  // Debug:   4 ticks × 15 s = 60 s  (1 minute)
  // Release: 60 ticks × 15 s = 900 s (15 minutes)

  static int get _captureEveryNTicks => kDebugMode ? 4 : 60;
  int _ticksSinceCapture = 0;

  // ── Lifecycle ────────────────────────────────────────────────────────────

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await _ensureFirebase();

    final prefs = await SharedPreferences.getInstance();
    final patientId = prefs.getString(kPatientIdPrefKey);

    if (patientId == null || patientId.isEmpty) {
      debugPrint('[BGTask] No patientId in prefs — waiting for login.');
      return;
    }

    await _startServices(patientId);
  }

  /// Fires every 15 seconds.
  /// Responsibilities:
  ///   1. Retry _startServices if login hadn't happened yet at onStart.
  ///   2. Count ticks and trigger captureAndSave + syncNow at threshold.
  @override
  void onRepeatEvent(DateTime timestamp) async {
    // ── Retry path ────────────────────────────────────────────────────────
    if (!_trackingStarted) {
      await _ensureFirebase();
      final prefs = await SharedPreferences.getInstance();
      final patientId = prefs.getString(kPatientIdPrefKey);
      if (patientId != null && patientId.isNotEmpty) {
        await _startServices(patientId);
      }
      return;
    }

    // ── Capture + sync path ───────────────────────────────────────────────
    _ticksSinceCapture++;
    debugPrint(
      '[BGTask] Tick $_ticksSinceCapture/$_captureEveryNTicks '
          '(${kDebugMode ? "debug: 1 min" : "release: 15 min"})',
    );

    if (_ticksSinceCapture >= _captureEveryNTicks) {
      _ticksSinceCapture = 0;
      await _captureAndSync();
    }
  }

  /// Fast path when app is open — UI sends patientId immediately on login.
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
    _locationService.stopTracking();
    _pocketCheckService?.dispose();
    await _historyService.dispose();
    _trackingStarted = false;
    _activePatientId = null;
    debugPrint('[BGTask] Service destroyed.');
  }

  // ── Notification callbacks ────────────────────────────────────────────────

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
    }
  }

  Future<void> _startServices(String patientId) async {
    _activePatientId = patientId;

    // Real-time live location → Firestore (for the tracker map)
    await _locationService.startTracking(patientId: patientId);

    // Firestore listener for caregiver-triggered pocket check
    _pocketCheckService = PocketCheckService(patientId: patientId);
    _pocketCheckService!.initialize();

    _trackingStarted = true;

    // Capture + sync immediately on start — don't wait for first tick
    await _captureAndSync();
    _ticksSinceCapture = 0;

    debugPrint('[BGTask] Services started for $patientId');
  }

  /// The core pipeline: GPS fix → SQLite → Firestore.
  /// This is the ONLY place captureAndSave + syncNow are called.
  Future<void> _captureAndSync() async {
    if (_activePatientId == null) return;
    final patientId = _activePatientId!;

    debugPrint('[BGTask] Capturing location for $patientId');

    // Step 1: GPS → SQLite (synced = 0)
    await _historyService.captureAndSave(patientId);

    // Step 2: SQLite → Firestore (marks rows synced = 1)
    // This is what makes data visible to the caregiver's History page.
    await _historyService.syncNow(patientId);

    debugPrint('[BGTask] Capture + sync complete for $patientId');
  }
}