import 'package:flutter/material.dart';

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
      home: const PatientDashboard(),
    );
  }
}

class PatientDashboard extends StatefulWidget {
  const PatientDashboard({super.key});

  @override
  State<PatientDashboard> createState() => _PatientDashboardState();
}

class _PatientDashboardState extends State<PatientDashboard> {
  int _selectedIndex = 0;

  // Colors matching the design
  static const Color limeGreen = Color(0xFFB5E800);
  static const Color purple = Color(0xFF8B5CF6);
  static const Color crimsonRed = Color(0xFFCC0000);
  static const Color darkBg = Color(0xFF1A1A1A);
  static const Color darkCard = Color(0xFF252525);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: darkBg,
      body: SafeArea(
        child: Column(
          children: [
            // Top flower header
            _buildFlowerHeader(),
            // Scrollable content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    // HELP ME button
                    _buildHelpMeButton(),
                    const SizedBox(height: 14),
                    // 2x2 grid of action buttons
                    _buildActionGrid(),
                    const SizedBox(height: 14),
                    // Fix the Clock button
                    _buildFixTheClockButton(),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
            // Bottom navigation
            _buildBottomNav(),
          ],
        ),
      ),
    );
  }

  Widget _buildFlowerHeader() {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        // The green flower blob shape
        CustomPaint(
          painter: FlowerBlobPainter(),
          child: Container(
            width: double.infinity,
            height: 110,
            alignment: Alignment.center,
            child: Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Good Morning, RAJ',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'WED, 4 MARCH',
                    style: TextStyle(
                      color: Colors.black.withOpacity(0.7),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHelpMeButton() {
    return GestureDetector(
      onTap: () => _showAlert(context, 'HELP ME', 'Emergency alert sent to caregivers!'),
      child: Container(
        width: double.infinity,
        height: 72,
        decoration: BoxDecoration(
          color: crimsonRed,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: crimsonRed.withOpacity(0.5),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Center(
          child: Text(
            'HELP ME',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: 3,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionGrid() {
    return Row(
      children: [
        // Left column
        Expanded(
          child: Column(
            children: [
              _buildActionButton(
                icon: Icons.location_on_rounded,
                label: 'LOCATION',
                color: const Color(0xFFB5E800),
                iconColor: Colors.black,
                textColor: Colors.black,
                onTap: () => _showAlert(context, 'Location', 'Sharing your location...'),
              ),
              const SizedBox(height: 12),
              _buildActionButton(
                icon: Icons.home_rounded,
                label: 'TAKE ME\nHOME',
                color: purple,
                iconColor: Colors.white,
                textColor: Colors.white,
                onTap: () => _showAlert(context, 'Navigate Home', 'Starting navigation home...'),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // Right column
        Expanded(
          child: Column(
            children: [
              _buildActionButton(
                icon: Icons.phone_rounded,
                label: 'CALL FAMILY',
                color: purple,
                iconColor: Colors.white,
                textColor: Colors.white,
                onTap: () => _showAlert(context, 'Call Family', 'Calling your family...'),
              ),
              const SizedBox(height: 12),
              _buildActionButton(
                icon: Icons.medical_services_rounded,
                label: 'MEDICINE',
                color: purple,
                iconColor: Colors.white,
                textColor: Colors.white,
                onTap: () => _showAlert(context, 'Medicine', 'Opening medicine schedule...'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required Color iconColor,
    required Color textColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 105,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
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
            Icon(icon, color: iconColor, size: 38),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: textColor,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFixTheClockButton() {
    return GestureDetector(
      onTap: () => _showAlert(context, 'Fix the Clock', 'Starting Clock Drawing Test...'),
      child: Container(
        width: double.infinity,
        height: 90,
        decoration: BoxDecoration(
          color: const Color(0xFFB5E800),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFB5E800).withOpacity(0.4),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            const Expanded(
              child: Padding(
                padding: EdgeInsets.only(left: 20),
                child: Text(
                  'FIX THE\nCLOCK',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                    height: 1.15,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 20),
              child: Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.black,
                  size: 36,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      height: 72,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(40),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildNavItem(Icons.home_rounded, 0),
          _buildNavItem(Icons.settings_rounded, 1),
        ],
      ),
    );
  }

  Widget _buildNavItem(IconData icon, int index) {
    final bool isSelected = _selectedIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFB5E800).withOpacity(0.2)
              : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: isSelected ? const Color(0xFFB5E800) : Colors.white54,
          size: 30,
        ),
      ),
    );
  }

  void _showAlert(BuildContext context, String title, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$title: $message'),
        backgroundColor: const Color(0xFF8B5CF6),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

/// CustomPainter that draws the flower/blob shape at the top
/// matching the "top-flower-blob" PNG design
class FlowerBlobPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFB5E800)
      ..style = PaintingStyle.fill;

    final path = Path();

    // The organic flower blob shape:
    // Main rectangle body
    final double w = size.width;
    final double h = size.height;

    // Start from bottom-left
    path.moveTo(0, h);
    path.lineTo(0, h * 0.55);

    // Left petal notch — curves up toward the left petal
    path.cubicTo(
      w * 0.05, h * 0.4,
      w * 0.10, h * 0.1,
      w * 0.18, h * 0.08,
    );
    // Left petal tip
    path.cubicTo(
      w * 0.24, h * 0.05,
      w * 0.28, h * 0.22,
      w * 0.30, h * 0.30,
    );

    // Center notch dip between left and center petal
    path.cubicTo(
      w * 0.33, h * 0.38,
      w * 0.37, h * 0.32,
      w * 0.40, h * 0.28,
    );

    // Center petal going up
    path.cubicTo(
      w * 0.44, h * 0.10,
      w * 0.50, -h * 0.05,
      w * 0.50, -h * 0.10,
    );
    // Center petal down the other side
    path.cubicTo(
      w * 0.50, -h * 0.05,
      w * 0.56, h * 0.10,
      w * 0.60, h * 0.28,
    );

    // Center-right notch
    path.cubicTo(
      w * 0.63, h * 0.32,
      w * 0.67, h * 0.38,
      w * 0.70, h * 0.30,
    );

    // Right petal going up
    path.cubicTo(
      w * 0.72, h * 0.22,
      w * 0.76, h * 0.05,
      w * 0.82, h * 0.08,
    );
    // Right petal tip
    path.cubicTo(
      w * 0.90, h * 0.10,
      w * 0.95, h * 0.4,
      w, h * 0.55,
    );

    path.lineTo(w, h);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}