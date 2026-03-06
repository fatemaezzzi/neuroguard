import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'core/services/permission_service.dart';
import 'features/caregiver/cognitest_history_screen.dart';
import 'features/caregiver/caregiver_home.dart';
import 'core/services/permission_service.dart';
import 'features/caregiver/vitals_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized(); // Required before any async work

  await PermissionService.requestAllPermissions(); // Request mic, camera, location

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
      home: const CogniTestHistoryScreen(),
    );
  }
}