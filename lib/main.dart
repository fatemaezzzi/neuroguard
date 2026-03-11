import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'core/services/permission_service.dart';
import 'core/services/location_service.dart'; // auto-start GPS on launch
import 'features/patient/patient_home.dart';
import 'features/caregiver/caregiver_home.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      name: 'neuroguard',          // give it an explicit unique name
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  try {
    final result = await FirebaseFirestore.instance
        .collection('users')
        .limit(1)
        .get(const GetOptions(source: Source.server));
    print('✅ FIRESTORE WORKS: ${result.docs.length} docs found');
  } catch (e) {
    print('❌ FIRESTORE FAILED: $e');
  }

  await PermissionService.requestAllPermissions();

  // ── Auto-start GPS tracking on the patient device ─────────────────────────
  // This is the key fix: without this, location never pushes to Firestore
  // and the caregiver map stays frozen. startTracking() is safe to call here
  // — it's a singleton, guards against double-starts internally, and runs
  // a 30-second periodic timer in the background for the life of the app.
  //
  // TODO: Replace 'patient_01' with the real auth UID once login is wired.
  await LocationService().initialise();
  unawaited(LocationService().startTracking(patientId: 'patient_01'));

  runApp(const NeuroGuardApp());
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
      home: const PatientHome(),
    );
  }
}