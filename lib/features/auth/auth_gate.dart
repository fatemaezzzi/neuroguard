import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:neuroguard/core/providers/auth_providers.dart';
import 'package:neuroguard/features/auth/login_screen.dart';
import 'package:neuroguard/features/auth/patient_scan_screen.dart';
import 'package:neuroguard/features/caregiver/caregiver_home.dart';
import 'package:neuroguard/features/patient/patient_home.dart';

class AuthGate extends ConsumerWidget {        // ← was StatelessWidget
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {   // ← WidgetRef added
    final authState = ref.watch(authStateProvider);
    final userDataAsync = ref.watch(userDataProvider);

    return authState.when(
      loading: () => const _LoadingScreen(),
      error: (_, __) => const LoginScreen(),
      data: (user) {
        if (user == null) return const LoginScreen();

        return userDataAsync.when(
          loading: () => const _LoadingScreen(),
          error: (_, __) => const LoginScreen(),
          data: (data) {
            if (data == null) {
              FirebaseAuth.instance.signOut();
              return const LoginScreen();
            }

            final role = data['role'] as String? ?? 'patient';
            final isPaired = data['is_paired'] == true;
            final uid = user.uid;

            if (role == 'caregiver') return const CaregiverHomePage();
            if (!isPaired) return PatientScanScreen(patientId: uid);
            return PatientHome(patientId: uid);
          },
        );
      },
    );
  }
}

// _LoadingScreen stays exactly the same — no changes needed
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