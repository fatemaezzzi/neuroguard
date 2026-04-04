import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'core/services/permission_service.dart';
import 'core/services/location_service.dart';
import 'core/services/background_task_handler.dart';
import 'firebase_options.dart';
import 'features/auth/auth_gate.dart';

/// Background FCM handler — must be top-level
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('Background FCM message received: ${message.messageId}');
}

/// Call this right after login with the patient's uid.
/// Saves uid to SharedPreferences AND sends it to the running background
/// isolate immediately so the Firestore listeners start without delay.
Future<void> activatePatientBackground(String uid) async {
  await savePatientIdForBackground(uid);
  FlutterForegroundTask.sendDataToTask({'patientId': uid});
}

/// Call this on logout.
Future<void> deactivatePatientBackground() async {
  await clearPatientIdForBackground();
  await FlutterForegroundTask.stopService();
}

/// Saves FCM token to Firestore under users/{uid}
Future<void> saveFcmToken(String uid) async {
  try {
    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional) {
      final token = await messaging.getToken();
      if (token != null) {
        await FirebaseFirestore.instance.collection('users').doc(uid).set(
          {'fcmToken': token, 'fcmTokenUpdatedAt': FieldValue.serverTimestamp()},
          SetOptions(merge: true),
        );
        debugPrint('FCM token saved: $token');
      }
      messaging.onTokenRefresh.listen((newToken) async {
        await FirebaseFirestore.instance.collection('users').doc(uid).set(
          {'fcmToken': newToken, 'fcmTokenUpdatedAt': FieldValue.serverTimestamp()},
          SetOptions(merge: true),
        );
      });
    }
  } catch (e) {
    debugPrint('Failed to save FCM token: $e');
  }
}

/// Configures foreground task — must be called before startService()
void _initForegroundTask() {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'neuroguard_bg',
      channelName: 'NeuroGuard Monitoring',
      channelDescription: 'Keeps patient monitoring active in the background',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: false,
      playSound: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      // Retry every 15s in case patientId wasn't in prefs yet on first start
      eventAction: ForegroundTaskEventAction.repeat(15000),
      autoRunOnBoot: true,             // survive device reboot
      autoRunOnMyPackageReplaced: true, // survive app update
      allowWakeLock: true,             // prevent CPU sleep
      allowWifiLock: true,             // keep Firestore connection alive
    ),
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // MUST be before runApp — initialises the port that lets the background
  // isolate communicate back to the UI isolate
  FlutterForegroundTask.initCommunicationPort();

  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  await PermissionService.requestAllPermissions();
  await LocationService().initialise();

  // Configure foreground task options
  _initForegroundTask();

  // Start the persistent background service.
  // startCallback (in background_task_handler.dart) runs in a separate isolate.
  // It reads patientId from SharedPreferences so it works even after app kill.
  // TODO: gate behind patient-role check once userRole provider is wired.
  await FlutterForegroundTask.startService(
    serviceId: 256,
    notificationTitle: 'NeuroGuard Active',
    notificationText: 'Patient monitoring is running',
    callback: startCallback,
  );

  runApp(
    const ProviderScope(
      child: NeuroGuardApp(),
    ),
  );
}

class NeuroGuardApp extends StatelessWidget {
  const NeuroGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    // WithForegroundTask ties the service lifecycle to the widget tree —
    // prevents the service being orphaned if the widget tree is rebuilt
    return WithForegroundTask(
      child: MaterialApp(
        title: 'NeuroGuard',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          scaffoldBackgroundColor: const Color(0xFF0A0A0A),
          textTheme: GoogleFonts.robotoTextTheme(
            Theme.of(context).textTheme,
          ),
        ),
        home: const AuthGate(),
      ),
    );
  }
}