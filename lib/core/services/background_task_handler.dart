import 'package:flutter/cupertino.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:neuroguard/core/services/location_service.dart';
import 'package:neuroguard/core/services/pocket_check_service.dart';
import 'package:neuroguard/firebase_options.dart';

// Key used to persist patientId so the background isolate can read it
// even when the UI isolate (main app) is fully closed.
const String kPatientIdPrefKey = 'neuroguard_patient_id';

/// Saves patientId to SharedPreferences — call this right after login.
Future<void> savePatientIdForBackground(String patientId) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(kPatientIdPrefKey, patientId);
}

/// Clears the stored patientId — call this on logout.
Future<void> clearPatientIdForBackground() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(kPatientIdPrefKey);
}

/// Called by the foreground service isolate — must be a top-level function.
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(BackgroundTaskHandler());
}

class BackgroundTaskHandler extends TaskHandler {
  final LocationService _locationService = LocationService();
  PocketCheckService? _pocketCheckService;
  bool _trackingStarted = false;

  /// Called once when the foreground service starts — including after device
  /// reboot or app kill.
  ///
  /// IMPORTANT: this runs in a SEPARATE Dart isolate from the UI.
  /// Firebase must be explicitly initialised here before any Firestore
  /// or FCM calls — it is NOT inherited from the main isolate.
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // 1. Initialise Firebase in this isolate — required for Firestore to work
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }

    // 2. Read patientId from SharedPreferences — no UI isolate needed
    final prefs = await SharedPreferences.getInstance();
    final patientId = prefs.getString(kPatientIdPrefKey);

    if (patientId == null || patientId.isEmpty) {
      debugPrint('[BackgroundTaskHandler] No patientId in prefs — waiting.');
      return;
    }

    await _startServices(patientId);
  }

  /// Called every 15 seconds. Retries if onStart missed the patientId
  /// (e.g. very first launch before login has saved it to prefs).
  @override
  void onRepeatEvent(DateTime timestamp) async {
    if (_trackingStarted) return;

    // Ensure Firebase is up before trying Firestore
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }

    final prefs = await SharedPreferences.getInstance();
    final patientId = prefs.getString(kPatientIdPrefKey);
    if (patientId != null && patientId.isNotEmpty) {
      await _startServices(patientId);
    }
  }

  /// Fast path when the app IS open — UI isolate sends patientId immediately
  /// after login via: FlutterForegroundTask.sendDataToTask({'patientId': uid})
  @override
  void onReceiveData(Object data) async {
    if (data is Map<String, dynamic> && data.containsKey('patientId')) {
      final patientId = data['patientId'] as String;
      if (_trackingStarted) return;

      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }

      await _startServices(patientId);
    }
  }

  Future<void> _startServices(String patientId) async {
    // LocationService uses Firestore — Firebase must be initialised first
    await _locationService.startTracking(patientId: patientId);

    // PocketCheckService uses Firestore snapshot listener for caregiver trigger
    _pocketCheckService = PocketCheckService(patientId: patientId);
    _pocketCheckService!.initialize();

    _trackingStarted = true;
    debugPrint('[BackgroundTaskHandler] Services started for $patientId');
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _locationService.stopTracking();
    _pocketCheckService?.dispose();
    _trackingStarted = false;
    debugPrint('[BackgroundTaskHandler] Service destroyed.');
  }

  @override
  void onNotificationButtonPressed(String id) {}

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp('/');
  }

  @override
  void onNotificationDismissed() {}
}