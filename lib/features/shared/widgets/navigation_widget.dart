import 'package:flutter/material.dart';

// ── Patient Bottom Nav ─────────────────────────────────────────────────────
class PatientBottomNav extends StatelessWidget {
  final VoidCallback onSettingsTap;
  // BUG FIX 1: optional override so history screen can route to PatientHome
  final VoidCallback? onHomeTap;

  const PatientBottomNav({
    super.key,
    required this.onSettingsTap,
    this.onHomeTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        GestureDetector(
          onTap: onHomeTap ??
                  () {
                Navigator.pushNamedAndRemoveUntil(
                    context, '/', (route) => false);
              },
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
    );
  }
}

// ── Caregiver Bottom Nav ───────────────────────────────────────────────────
class CaregiverBottomNav extends StatelessWidget {
  final VoidCallback onSettingsTap;
  // BUG FIX 1: optional override so history screen can route to CaregiverHome
  final VoidCallback? onHomeTap;

  const CaregiverBottomNav({
    super.key,
    required this.onSettingsTap,
    this.onHomeTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        GestureDetector(
          onTap: onHomeTap ??
                  () {
                Navigator.pushNamedAndRemoveUntil(
                    context, '/', (route) => false);
              },
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
    );
  }
}