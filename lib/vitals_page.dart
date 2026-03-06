import 'package:flutter/material.dart';
import 'dart:math' as math;

void main() {
  runApp(const NeuroGuardApp());
}

class NeuroGuardApp extends StatelessWidget {
  const NeuroGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const VitalsPage(),
    );
  }
}

class VitalsPage extends StatefulWidget {
  const VitalsPage({super.key});

  @override
  State<VitalsPage> createState() => _VitalsPageState();
}

class _VitalsPageState extends State<VitalsPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Simulated sensor data
  final String _currentStatus = 'SLEEPING';
  final String _statusDetail = 'low movement, on bed';
  final String _lastVibrationTime = '10:30';
  final String _devicePresence = 'ON PERSON';
  final List<double> _velostatData = [
    0.2, 0.3, 0.25, 0.4, 0.35, 0.3, 0.28,
    0.32, 0.29, 0.31, 0.27, 0.33, 0.30, 0.28,
    0.35, 0.32, 0.30, 0.29, 0.31, 0.28, 0.26,
    0.30, 0.33, 0.31, 0.29, 0.28, 0.27, 0.30,
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            children: [
              // ─── TOP NAV ───────────────────────────────────────────
              _buildTopNav(),
              const SizedBox(height: 24),

              // ─── VELOSTAT GRAPH BLOB ───────────────────────────────
              _buildVelostatGraphCard(),
              const SizedBox(height: 12),

              // ─── STATUS CARD ───────────────────────────────────────
              _buildStatusCard(),
              const SizedBox(height: 20),

              // ─── POCKET CHECK ──────────────────────────────────────
              _buildPocketCheckCard(),
              const SizedBox(height: 12),

              // ─── LAST VIBRATION TEST ───────────────────────────────
              _buildLastVibrationCard(),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),

      // ─── BOTTOM NAV ─────────────────────────────────────────────────
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // TOP NAV
  // ─────────────────────────────────────────────────────────────────────
  Widget _buildTopNav() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'NEUROGUARD',
          style: TextStyle(
            color: const Color(0xFFCCFF00),
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 4,
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // VELOSTAT GRAPH CARD — large gradient blob with live graph inside
  // ─────────────────────────────────────────────────────────────────────
  Widget _buildVelostatGraphCard() {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _pulseAnimation.value,
          child: child,
        );
      },
      child: Container(
        width: double.infinity,
        height: 200,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(40),
          gradient: const RadialGradient(
            center: Alignment(0.1, 0.1),
            radius: 0.8,
            colors: [
              Color(0xFFCCFF00),   // neon yellow-green centre
              Color(0xFF8B5CF6),   // purple edge
              Color(0xFF6D28D9),
            ],
            stops: [0.0, 0.6, 1.0],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFCCFF00).withOpacity(0.18),
              blurRadius: 30,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Stack(
          children: [
            // Label
            const Positioned(
              top: 24,
              left: 28,
              child: Text(
                'VELOSTAT GRAPH',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  letterSpacing: 1.5,
                ),
              ),
            ),
            // Mini waveform
            Positioned(
              bottom: 28,
              left: 20,
              right: 20,
              child: _buildMiniWaveform(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniWaveform() {
    return SizedBox(
      height: 60,
      child: CustomPaint(
        painter: _WaveformPainter(_velostatData),
        size: const Size(double.infinity, 60),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // STATUS CARD
  // ─────────────────────────────────────────────────────────────────────
  Widget _buildStatusCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF9B59B6),
            Color(0xFF7B2D8B),
            Color(0xFFCCFF00),
          ],
          stops: [0.0, 0.5, 1.5],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'STATUS',
            style: TextStyle(
              color: const Color(0xFFCCFF00),
              fontWeight: FontWeight.w900,
              fontSize: 20,
              letterSpacing: 2,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _currentStatus,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                  letterSpacing: 1,
                ),
              ),
              Text(
                _statusDetail,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // POCKET CHECK CARD
  // ─────────────────────────────────────────────────────────────────────
  Widget _buildPocketCheckCard() {
    return GestureDetector(
      onTap: () {
        // Navigate to pocket check detail
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Running Pocket Check...'),
            backgroundColor: Color(0xFF7C3AED),
            duration: Duration(seconds: 1),
          ),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        decoration: BoxDecoration(
          color: const Color(0xFF7C3AED),
          borderRadius: BorderRadius.circular(40),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF7C3AED).withOpacity(0.4),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'POCKET CHECK',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 20,
                letterSpacing: 1.5,
              ),
            ),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFCCFF00),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.north_east,
                color: Colors.black,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // LAST VIBRATION TEST CARD
  // ─────────────────────────────────────────────────────────────────────
  Widget _buildLastVibrationCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
      decoration: BoxDecoration(
        color: const Color(0xFF6D28D9),
        borderRadius: BorderRadius.circular(36),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6D28D9).withOpacity(0.35),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text(
            'LAST VIBRATION TEST',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 17,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _lastVibrationTime,
            style: TextStyle(
              color: Colors.white.withOpacity(0.75),
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _devicePresence,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 17,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // BOTTOM NAV  (Home + Settings pills matching the screenshots)
  // ─────────────────────────────────────────────────────────────────────
  Widget _buildBottomNav() {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Home button
          _NavButton(
            icon: Icons.home_rounded,
            isActive: false,
            onTap: () {},
          ),
          // Settings button
          _NavButton(
            icon: Icons.settings_rounded,
            isActive: false,
            onTap: () {},
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// NAV BUTTON WIDGET
// ─────────────────────────────────────────────────────────────────────────
class _NavButton extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const _NavButton({
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 62,
        height: 62,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF111111),
          border: Border.all(
            color: const Color(0xFF222222),
            width: 1.5,
          ),
        ),
        child: Icon(
          icon,
          color: const Color(0xFFCCFF00),
          size: 28,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// WAVEFORM PAINTER — draws the velostat pressure graph
// ─────────────────────────────────────────────────────────────────────────
class _WaveformPainter extends CustomPainter {
  final List<double> data;

  _WaveformPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final paint = Paint()
      ..color = Colors.black.withOpacity(0.7)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.black.withOpacity(0.4),
          Colors.black.withOpacity(0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    final path = Path();
    final fillPath = Path();

    final stepX = size.width / (data.length - 1);
    final minVal = data.reduce(math.min);
    final maxVal = data.reduce(math.max);
    final range = maxVal - minVal == 0 ? 1.0 : maxVal - minVal;

    double x = 0;
    double y = size.height - ((data[0] - minVal) / range) * size.height;
    path.moveTo(x, y);
    fillPath.moveTo(x, size.height);
    fillPath.lineTo(x, y);

    for (int i = 1; i < data.length; i++) {
      x = i * stepX;
      y = size.height - ((data[i] - minVal) / range) * size.height;

      final prevX = (i - 1) * stepX;
      final cpX = prevX + stepX / 2;
      path.cubicTo(cpX, path.getBounds().bottom, cpX, y, x, y);
      fillPath.lineTo(x, y);
    }

    fillPath.lineTo(x, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);

    // Draw dots at each data point
    final dotPaint = Paint()
      ..color = Colors.black.withOpacity(0.8)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < data.length; i++) {
      final px = i * stepX;
      final py = size.height - ((data[i] - minVal) / range) * size.height;
      canvas.drawCircle(Offset(px, py), 2.5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) => old.data != data;
}