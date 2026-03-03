import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'caregiver_home.dart';

void main() {
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
      home: const CaregiverHomePage(),
    );
  }
}