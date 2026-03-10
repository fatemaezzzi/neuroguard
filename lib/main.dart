
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'core/services/permission_service.dart';
import 'features/patient/patient_home.dart';
import 'features/caregiver/caregiver_home.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
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
