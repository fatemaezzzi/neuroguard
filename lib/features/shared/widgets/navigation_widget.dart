import 'package:flutter/material.dart';
import 'package:neuroguard/features/patient/patient_home.dart';
import 'package:neuroguard/features/caregiver/caregiver_home.dart';

/// Reusable bottom nav for the PATIENT app.
/// Home → PatientHome, Settings → onSettingsTap
///
/// Usage:
/// ```dart
/// PatientBottomNav(onSettingsTap: () {})
/// ```
class PatientBottomNav extends StatelessWidget {
  final VoidCallback onSettingsTap;

  const PatientBottomNav({
    super.key,
    required this.onSettingsTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () => Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const PatientHome()),
                  (route) => false,
            ),
            child: Image.asset(
              'assets/glassbubble.png',
              width: 90,
              height: 90,
            ),
          ),
          GestureDetector(
            onTap: onSettingsTap,
            child: Image.asset(
              'assets/settingsblob.png',
              width: 90,
              height: 90,
            ),
          ),
        ],
      ),
    );
  }
}

/// Reusable bottom nav for the CAREGIVER app.
/// Home → CaregiverHome, Settings → onSettingsTap
///
/// Usage:
/// ```dart
/// CaregiverBottomNav(onSettingsTap: () {})
/// ```
class CaregiverBottomNav extends StatelessWidget {
  final VoidCallback onSettingsTap;

  const CaregiverBottomNav({
    super.key,
    required this.onSettingsTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () => Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const CaregiverHome()),
                  (route) => false,
            ),
            child: Image.asset(
              'assets/glassbubble.png',
              width: 62,
              height: 62,
            ),
          ),
          GestureDetector(
            onTap: onSettingsTap,
            child: Image.asset(
              'assets/settingsblob.png',
              width: 62,
              height: 62,
            ),
          ),
        ],
      ),
    );
  }
}