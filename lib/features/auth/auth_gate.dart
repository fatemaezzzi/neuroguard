import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:neuroguard/core/services/auth_service.dart';
import 'package:neuroguard/features/auth/login_screen.dart';
import 'package:neuroguard/features/auth/patient_scan_screen.dart';
import 'package:neuroguard/features/caregiver/caregiver_home.dart';
import 'package:neuroguard/features/patient/patient_home.dart';

// The root widget that decides what screen to show.
// 1. Not logged in → LoginScreen
// 2. Logged in as patient, not paired → PatientScanScreen (force pairing)
// 3. Logged in as patient, paired → PatientHome
// 4. Logged in as caregiver → CaregiverHome
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        // Still checking auth state
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScreen();
        }

        // Not logged in
        if (!authSnapshot.hasData || authSnapshot.data == null) {
          return const LoginScreen();
        }

        // Logged in — check role and pairing status
        return FutureBuilder<Map<String, dynamic>?>(
          future: AuthService().getUserData(),
          builder: (context, userSnapshot) {
            if (userSnapshot.connectionState == ConnectionState.waiting) {
              return const _LoadingScreen();
            }

            final data = userSnapshot.data;
            if (data == null) {
              // User doc missing — sign out and go to login
              FirebaseAuth.instance.signOut();
              return const LoginScreen();
            }

            final role = data['role'] as String? ?? 'patient';
            final isPaired = data['is_paired'] == true;
            final uid = FirebaseAuth.instance.currentUser!.uid;

            if (role == 'caregiver') {
            return const CaregiverHomePage();
            }

            // Patient — check if paired
            if (!isPaired) {
              // Force them to pair before accessing the app
              return PatientScanScreen(patientId: uid);
            }

            return const PatientHome();
          },
        );
      },
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFF7B4FD4)),
            SizedBox(height: 16),
            Text(
              'NEUROGUARD',
              style: TextStyle(
                color: Color(0xFFCCFF00),
                fontWeight: FontWeight.w900,
                fontSize: 18,
                letterSpacing: 3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}