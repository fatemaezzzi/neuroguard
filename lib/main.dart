import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'core/services/permission_service.dart';
import 'core/services/location_service.dart';
import 'core/services/spy_call_service.dart';
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
      autoRunOnBoot: true,              // survive device reboot
      autoRunOnMyPackageReplaced: true, // survive app update
      allowWakeLock: true,              // prevent CPU sleep
      allowWifiLock: true,              // keep Firestore connection alive
    ),
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── MUST be synchronous before runApp ────────────────────────────────────
  // initCommunicationPort() sets up a ReceivePort — it must run before the
  // background isolate tries to send messages, but is NOT async and does
  // not block the UI.
  FlutterForegroundTask.initCommunicationPort();

  // ── Firebase init is the only true blocker ───────────────────────────────
  // Auth state restoration needs Firebase ready before AuthGate renders,
  // otherwise FirebaseAuth.instance.authStateChanges() throws immediately.
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  // Register background FCM handler — synchronous, no await needed.
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Configure foreground task options — synchronous, no await needed.
  _initForegroundTask();

  // ── Paint the UI immediately ─────────────────────────────────────────────
  // Everything below (permissions, Agora, LocationService, foreground service)
  // is deferred to after the first frame so the user sees the AuthGate /
  // splash instantly instead of staring at a blank screen for 1-3 seconds.
  runApp(
    const ProviderScope(
      child: NeuroGuardApp(),
    ),
  );

  // ── Post-frame deferred initialisation ───────────────────────────────────
  // Runs after the first frame is painted. Order matters:
  //   1. Permissions  — fast when already granted (now run in parallel)
  //   2. LocationService — notification plugin setup (~50 ms)
  //   3. SpyCallService  — Agora engine (~200-400 ms, heaviest item)
  //   4. Foreground service — PATIENT ROLE ONLY, not caregivers
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await PermissionService.requestAllPermissions();
    await LocationService().initialise();

    // Agora init is deferred here instead of blocking main().
    // SpyCallService features are only used after navigation to SpyCallPage
    // so it is safe to initialise after first paint.
    await SpyCallService.init();

    // ── Foreground service: PATIENT ROLE ONLY ────────────────────────────
    // Previously this started for ALL users (including caregivers), spawning
    // an extra background Flutter engine + Geolocator instance — visible in
    // your logs as "Connected engine count 3" and "Skipped 49 frames".
    //
    // Now we gate it behind a role check. The service still auto-starts on
    // reboot via autoRunOnBoot:true so patients who reboot are still covered.
    // Caregivers are completely excluded — this eliminates the duplicate
    // engine problem and the main-thread jank on the caregiver side.
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        // Cache-first: avoids a network round-trip on every launch.
        // Falls back gracefully on cache miss (first install).
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get(const GetOptions(source: Source.cache));

        final role = doc.data()?['role'] as String?;

        if (role == 'patient') {
          await FlutterForegroundTask.startService(
            serviceId: 256,
            notificationTitle: 'NeuroGuard Active',
            notificationText: 'Patient monitoring is running',
            callback: startCallback,
          );
        }
        // Caregivers skip the foreground service entirely.
        // activatePatientBackground() starts it on-demand after pairing.
      } catch (_) {
        // Not logged in yet, or cache miss on first install.
        // The login flow calls activatePatientBackground() which starts
        // the service for patients at the right time.
      }
    }
  });
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