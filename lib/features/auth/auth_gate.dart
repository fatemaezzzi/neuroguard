import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:neuroguard/core/providers/auth_providers.dart';
import 'package:neuroguard/features/auth/login_screen.dart';
import 'package:neuroguard/features/auth/patient_scan_screen.dart';
import 'package:neuroguard/features/caregiver/caregiver_home.dart';
import 'package:neuroguard/features/patient/patient_home.dart';

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final userDataAsync = ref.watch(userDataProvider);

    // ── Single loading check ───────────────────────────────────────────────
    if (authState.isLoading) return const _LoadingScreen();

    final user = authState.value;
    if (user == null) return const LoginScreen();

    // ── User is signed in — wait for Firestore data ────────────────────────
    if (userDataAsync.isLoading) return const _LoadingScreen();

    final data = userDataAsync.value;

    if (data == null) {
      // Doc missing — invalidate stale provider then sign out.
      // Critical for account switching: clears caregiver cache before
      // patient stream opens, preventing the buffering freeze.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.invalidate(userDataProvider);
        FirebaseAuth.instance.signOut();
      });
      return const _LoadingScreen();
    }

    // ── UID mismatch guard ─────────────────────────────────────────────────
    // If cached doc belongs to previous user (caregiver), hold on loading
    // screen until the new user's (patient's) stream emits their own doc.
    // Without this, the patient briefly sees caregiver's role and gets
    // routed to CaregiverHomePage for a flash before correcting itself.
    final dataUid = data['uid'] as String?;
    if (dataUid != null && dataUid != user.uid) {
      return const _LoadingScreen();
    }

    // ── Route by role ──────────────────────────────────────────────────────
    final role = data['role'] as String? ?? 'patient';
    final isPaired = data['is_paired'] == true;
    final uid = user.uid;

    if (role == 'caregiver') return const CaregiverHomePage();
    if (!isPaired) return PatientScanScreen(patientId: uid);
    return PatientHome(patientId: uid);
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