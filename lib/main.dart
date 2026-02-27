import 'package:flutter/material.dart';
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
        fontFamily: 'Arial',
      ),
      home: const CaregiverHomePage(),
    );
  }
}