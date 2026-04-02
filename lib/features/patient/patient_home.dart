import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:neuroguard/features/patient/cognitest_screen.dart';
import 'package:neuroguard/features/shared/widgets/navigation_widget.dart';
import 'package:neuroguard/features/patient/navigate_home_service.dart';
import 'package:neuroguard/features/shared/settings_screen.dart';
import 'package:neuroguard/core/services/auth_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PatientHome
// ─────────────────────────────────────────────────────────────────────────────
class PatientHome extends StatefulWidget {
  const PatientHome({super.key});

  @override
  State<PatientHome> createState() => _PatientHomeState();
}

class _PatientHomeState extends State<PatientHome> {
  final _authService = AuthService();

  String _patientName = '...';
  String _patientId = '';

  static const Color limeGreen  = Color(0xFFB5E800);
  static const Color purple     = Color(0xFF7B52D9);
  static const Color crimsonRed = Color(0xFFBB0000);
  static const Color darkBg     = Color(0xFF1A1A1A);

  bool _isLocating = false;

  @override
  void initState() {
    super.initState();
    _loadPatientData();
  }

  Future<void> _loadPatientData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final data = await _authService.getUserData();
    if (!mounted) return;

    setState(() {
      _patientName = data?['name'] as String? ?? 'Friend';
      _patientId = uid;
    });
  }

  // ── Get first name only for friendly greeting ──────────────────────────
  String get _firstName {
    final parts = _patientName.trim().split(' ');
    return parts.isNotEmpty ? parts[0].toUpperCase() : _patientName.toUpperCase();
  }

  // ── Format today's date ────────────────────────────────────────────────
  String get _todayDate {
    const days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    const months = [
      'JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE',
      'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER'
    ];
    final now = DateTime.now();
    final dayName = days[now.weekday - 1];
    final monthName = months[now.month - 1];
    return '$dayName, ${now.day} $monthName';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: darkBg,
      body: SafeArea(
        child: Column(
          children: [
            _buildFlowerHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: Column(
                  children: [
                    _buildHelpMeButton(),
                    const SizedBox(height: 12),
                    _buildUnevenGrid(),
                    const SizedBox(height: 12),
                    _buildFixTheClockButton(),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            // ── Bottom Nav ───────────────────────────────────────────
            PatientBottomNav(
              onSettingsTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
              onHomeTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PatientHome()),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────
  // FLOWER HEADER — real name + real date
  // ───────────────────────────────────────────────
  Widget _buildFlowerHeader() {
    return SizedBox(
      width: double.infinity,
      height: 220,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: Image.asset('assets/top-flower-blob.png',
                fit: BoxFit.fill),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Good Morning, $_firstName',
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 24,
                    fontFamily: 'MicrosoftSansSerifBold',
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _todayDate,
                  style: TextStyle(
                    color: Colors.black.withOpacity(0.65),
                    fontSize: 20,
                    fontFamily: 'MicrosoftSansSerifBold',
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────
  // HELP ME
  // ───────────────────────────────────────────────
  Widget _buildHelpMeButton() {
    return GestureDetector(
      onTap: () => _toast('Emergency alert sent to caregivers!'),
      child: Container(
        width: double.infinity,
        height: 100,
        decoration: BoxDecoration(
          color: crimsonRed,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: crimsonRed.withOpacity(0.55),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Center(
          child: Text(
            'HELP ME',
            style: TextStyle(
              color: Colors.white,
              fontFamily: 'MicrosoftSansSerifBold',
              fontSize: 30,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.0,
            ),
          ),
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────
  // UNEVEN 2 × 2 GRID
  // ───────────────────────────────────────────────
  Widget _buildUnevenGrid() {
    const double gap = 12;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── LEFT COLUMN ──
        Expanded(
          child: Column(
            children: [
              _buildLocationCell(),
              const SizedBox(height: gap),
              _gridCell(
                height: 105,
                color: purple,
                icon: Icons.phone_rounded,
                iconColor: Colors.white,
                label: 'CALL\nFAMILY',
                labelColor: Colors.white,
                onTap: () => _toast('Calling your family…'),
              ),
            ],
          ),
        ),

        const SizedBox(width: gap),

        // ── RIGHT COLUMN ──
        Expanded(
          child: Column(
            children: [
              _gridCell(
                height: 105,
                color: purple,
                icon: Icons.medical_services_rounded,
                iconColor: Colors.white,
                label: 'MEDICINE',
                labelColor: Colors.white,
                onTap: () => _toast('Opening medicine schedule…'),
              ),
              const SizedBox(height: gap),
              _gridCell(
                height: 140,
                color: purple,
                icon: Icons.people_rounded,
                iconColor: Colors.white,
                label: 'CAREGIVER',
                labelColor: Colors.white,
                onTap: () => _toast('Contacting caregiver…'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ───────────────────────────────────────────────
  // LOCATION cell
  // ───────────────────────────────────────────────
  Widget _buildLocationCell() {
    return GestureDetector(
      onTap: _isLocating ? null : _handleLocationTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        height: 140,
        decoration: BoxDecoration(
          color: _isLocating ? limeGreen.withOpacity(0.55) : limeGreen,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: limeGreen.withOpacity(0.35),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: _isLocating
            ? const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  color: Colors.black,
                  strokeWidth: 3,
                ),
              ),
              SizedBox(height: 10),
              Text(
                'FINDING\nROUTE…',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  height: 1.3,
                ),
              ),
            ],
          ),
        )
            : const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.location_on_rounded,
                color: Colors.black, size: 44),
            SizedBox(height: 8),
            Text(
              'LOCATION',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.black,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleLocationTap() async {
    setState(() => _isLocating = true);
    await Future.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    setState(() => _isLocating = false);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NavigateHomePage(patientId: _patientId),
      ),
    );
  }

  // ───────────────────────────────────────────────
  // FIX THE CLOCK
  // ───────────────────────────────────────────────
  Widget _buildFixTheClockButton() {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CogniTestScreen()),
      ),
      child: Container(
        width: double.infinity,
        height: 105,
        decoration: BoxDecoration(
          color: limeGreen,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: limeGreen.withOpacity(0.45),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            const Expanded(
              child: Padding(
                padding: EdgeInsets.only(left: 22),
                child: Text(
                  'FIX THE\nCLOCK',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 30,
                    fontFamily: 'MicrosoftSansSerifBold',
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                    height: 1.15,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 22),
              child: Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.black,
                  size: 40,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────
  // Generic grid cell builder
  // ───────────────────────────────────────────────
  Widget _gridCell({
    required double height,
    required Color color,
    required IconData icon,
    required Color iconColor,
    required String label,
    required Color labelColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.35),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: iconColor, size: 44),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: labelColor,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: purple,
        behavior: SnackBarBehavior.floating,
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}