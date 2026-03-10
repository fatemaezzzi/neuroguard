import 'package:flutter/material.dart';
import 'package:neuroguard/features/caregiver/cognitest_screen.dart';

void main() {
  runApp(const NeuroGuardApp());
}

class NeuroGuardApp extends StatelessWidget {
  const NeuroGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NeuroGuard Patient',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFF1A1A1A),
        fontFamily: 'Roboto',
      ),
      home: const PatientHome(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PatientHome — renamed as requested
// ─────────────────────────────────────────────────────────────────────────────
class PatientHome extends StatefulWidget {
  const PatientHome({super.key});

  @override
  State<PatientHome> createState() => _PatientHomeState();
}

class _PatientHomeState extends State<PatientHome> {
  int _selectedIndex = 0;

  static const Color limeGreen  = Color(0xFFB5E800);
  static const Color purple     = Color(0xFF7B52D9);
  static const Color crimsonRed = Color(0xFFBB0000);
  static const Color darkBg     = Color(0xFF1A1A1A);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: darkBg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top flower PNG with greeting overlay ──
            _buildFlowerHeader(),

            // ── Scrollable content area ──
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

            // ── Bottom navigation ──
            _buildBottomNav(),
          ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────
  // FLOWER HEADER — uses top-flower-blob.png asset
  // with greeting text stacked on top
  // ───────────────────────────────────────────────
  Widget _buildFlowerHeader() {
    return SizedBox(
      width: double.infinity,
      height: 220,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // The PNG asset fills the full width
          Positioned.fill(
            child: Image.asset(
              'assets/top-flower-blob.png',
              fit: BoxFit.fill,
            ),
          ),

          // Greeting text centred over the blob
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Good Morning, RAJ',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 24,
                    fontFamily: 'MicrosoftSansSerifBold',
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'WED, 4 MARCH',
                  style: TextStyle(
                    color: Colors.black.withOpacity(0.65),
                    fontSize: 20,
                    fontFamily: 'MicrosoftSanSerifBold',
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
  // HELP ME — full-width red button
  // ───────────────────────────────────────────────
  Widget _buildHelpMeButton() {
    return GestureDetector(
      onTap: () => _toast('Emergency alert sent to caregivers!'),
      child: Container(
        width: double.infinity,
        height: 70,
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
  //
  // Left column :  LOCATION (tall)  /  TAKE ME HOME (shorter)
  // Right column:  CALL FAMILY (shorter)  /  MEDICINE (tall)
  //
  // Achieved with IntrinsicHeight + flex heights via
  // explicit SizedBox heights on each cell.
  //
  // Heights (matching prototype):
  //   LOCATION      = 140
  //   TAKE ME HOME  = 105
  //   CALL FAMILY   = 105
  //   MEDICINE      = 140
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
              // LOCATION — taller
              _gridCell(
                height: 140,
                color: limeGreen,
                icon: Icons.location_on_rounded,
                iconColor: Colors.black,
                label: 'LOCATION',
                labelColor: Colors.black,
                onTap: () => _toast('Sharing your location…'),
              ),
              const SizedBox(height: gap),
              // TAKE ME HOME — shorter
              _gridCell(
                height: 105,
                color: purple,
                icon: Icons.home_rounded,
                iconColor: Colors.white,
                label: 'TAKE ME\nHOME',
                labelColor: Colors.white,
                onTap: () => _toast('Starting navigation home…'),
              ),
            ],
          ),
        ),

        const SizedBox(width: gap),

        // ── RIGHT COLUMN ──
        Expanded(
          child: Column(
            children: [
              // CALL FAMILY — shorter
              _gridCell(
                height: 105,
                color: purple,
                icon: Icons.phone_rounded,
                iconColor: Colors.white,
                label: 'CALL FAMILY',
                labelColor: Colors.white,
                onTap: () => _toast('Calling your family…'),
              ),
              const SizedBox(height: gap),
              // MEDICINE — taller
              _gridCell(
                height: 140,
                color: purple,
                icon: Icons.medical_services_rounded,
                iconColor: Colors.white,
                label: 'MEDICINE',
                labelColor: Colors.white,
                onTap: () => _toast('Opening medicine schedule…'),
              ),
            ],
          ),
        ),
      ],
    );
  }

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

  // ───────────────────────────────────────────────
  // FIX THE CLOCK — lime wide button with play icon
  // ───────────────────────────────────────────────
  Widget _buildFixTheClockButton() {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CogniTestScreen()),
      ),
      child: Container(
        width: double.infinity,
        height: 95,
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
  // BOTTOM NAV — large dark pill, huge icons
  // ───────────────────────────────────────────────
  Widget _buildBottomNav() {
    return Container(
      height: 88,
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF2B2B2B),
        borderRadius: BorderRadius.circular(44),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _navButton(Icons.home_rounded, 0),
          _navButton(Icons.settings_rounded, 1),
        ],
      ),
    );
  }

  Widget _navButton(IconData icon, int index) {
    final bool active = _selectedIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          // Subtle lime highlight on the active item
          color: active
              ? limeGreen.withOpacity(0.18)
              : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          // Active icon is lime-green; inactive is white
          color: active ? limeGreen : Colors.white,
          size: 46, // ← big icons as shown in the design
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────
  // Helper: show a floating snack-bar
  // ───────────────────────────────────────────────
  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: purple,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}