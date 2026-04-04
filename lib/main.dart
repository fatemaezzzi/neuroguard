import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'core/services/permission_service.dart';
import 'core/services/location_service.dart';
import 'firebase_options.dart';
import 'features/auth/auth_gate.dart';

/// Background message handler — must be a top-level function
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('Background FCM message received: ${message.messageId}');
}

/// Retrieves the FCM token and saves it to Firestore under users/{uid}
Future<void> saveFcmToken(String uid) async {
  try {
    final messaging = FirebaseMessaging.instance;

    // Request notification permission (iOS / macOS)
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

      // Refresh token whenever it rotates
      messaging.onTokenRefresh.listen((newToken) async {
        await FirebaseFirestore.instance.collection('users').doc(uid).set(
          {'fcmToken': newToken, 'fcmTokenUpdatedAt': FieldValue.serverTimestamp()},
          SetOptions(merge: true),
        );
        debugPrint('FCM token refreshed: $newToken');
      });
    }
  } catch (e) {
    debugPrint('Failed to save FCM token: $e');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  // Register background message handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  await PermissionService.requestAllPermissions();
  await LocationService().initialise();
  // GPS tracking will start after login once we have the real patient UID
  // LocationService().startTracking() is called from PatientHome after auth

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
    return MaterialApp(
      title: 'NeuroGuard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
        textTheme: GoogleFonts.robotoTextTheme(
          Theme.of(context).textTheme,
        ),
      ),
      home: const AuthGate(),
    );
  }
}