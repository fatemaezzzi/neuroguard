import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import 'package:zego_uikit_signaling_plugin/zego_uikit_signaling_plugin.dart';
import 'core/services/permission_service.dart';
import 'core/services/location_service.dart';
import 'firebase_options.dart';
import 'features/auth/auth_gate.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  await PermissionService.requestAllPermissions();
  await LocationService().initialise();
  // GPS tracking will start after login once we have the real patient UID
  // LocationService().startTracking() is called from PatientHome after auth

  runApp(
      const ProviderScope(
          child: NeuroGuardApp(),
      ),
  );
  // --- ZegoCloud init ---
  // Only init if a user is already logged in (returning user).
  // If not logged in yet, AuthGate will call this after login.
  final currentUser = FirebaseAuth.instance.currentUser;
  if (currentUser != null) {
    await _initZego(currentUser.uid, currentUser.displayName ?? 'NeuroGuard User');
  }

  runApp(const NeuroGuardApp());
}

/// Call this once after login with the real UID.
/// Safe to call multiple times — ZegoCloud handles duplicate inits gracefully.
Future<void> _initZego(String userID, String userName) async {
  await ZegoUIKitPrebuiltCallInvitationService().init(
    appID: 1206500765,
    appSign: '1ee0960ffb2f98300a7562bb14ae465cfa1519c24d7d987ea2db41e09716de57',
    userID: userID,
    userName: userName,
    plugins: [ZegoUIKitSignalingPlugin()],
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