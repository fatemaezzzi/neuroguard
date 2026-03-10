import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:neuroguard/features/patient/cognitest_screen.dart';
import 'core/services/permission_service.dart';
import 'features/caregiver/cognitest_history_screen.dart';
import 'features/patient/patient_home.dart';
import 'features/caregiver/caregiver_home.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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