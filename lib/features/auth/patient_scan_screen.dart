import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'dart:convert';
import 'package:neuroguard/core/services/auth_service.dart';
import 'package:neuroguard/features/patient/patient_home.dart';

// Shown to the patient right after they sign up.
// They scan the caregiver's QR code to link their accounts.
class PatientScanScreen extends StatefulWidget {
  final String patientId;

  const PatientScanScreen({super.key, required this.patientId});

  @override
  State<PatientScanScreen> createState() => _PatientScanScreenState();
}

class _PatientScanScreenState extends State<PatientScanScreen> {
  final _authService = AuthService();
  final _controller = MobileScannerController();

  bool _isProcessing = false;
  bool _paired = false;

  Future<void> _onBarcodeDetected(BarcodeCapture capture) async {
    // Prevent double-processing
    if (_isProcessing || _paired) return;

    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;

    setState(() => _isProcessing = true);
    _controller.stop();

    try {
      // Parse the JSON from the QR
      final Map<String, dynamic> data = jsonDecode(raw);

      // Validate it's a NeuroGuard pairing QR
      if (data['type'] != 'neuroguard_pairing' ||
          data['caregiver_id'] == null) {
        _showError('This QR code is not a valid NeuroGuard pairing code.');
        _controller.start();
        setState(() => _isProcessing = false);
        return;
      }

      final caregiverId = data['caregiver_id'] as String;
      final caregiverName = data['caregiver_name'] as String? ?? 'Your Caregiver';

      // Write pairing to Firestore
      await _authService.pairPatientToCaregiver(
        patientId: widget.patientId,
        caregiverId: caregiverId,
      );

      setState(() => _paired = true);

      // Show success then navigate
      if (!mounted) return;
      _showSuccess(caregiverName);
    } catch (e) {
      _showError('Failed to read QR code. Please try again.');
      _controller.start();
      setState(() => _isProcessing = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showSuccess(String caregiverName) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: Color(0xFF7B4FD4),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check, color: Colors.white, size: 36),
            ),
            const SizedBox(height: 16),
            const Text(
              'PAIRED!',
              style: TextStyle(
                color: Color(0xFFCCFF00),
                fontWeight: FontWeight.w900,
                fontSize: 22,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You are now linked with\n$caregiverName',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7B4FD4),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const PatientHome(patientId: '',)),
                        (route) => false,
                  );
                },
                child: const Text(
                  'Go to App',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                children: [
                  const Text(
                    'SCAN CAREGIVER QR',
                    style: TextStyle(
                      color: Color(0xFFCCFF00),
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Point your camera at the QR code\nshown on your caregiver\'s phone.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.5),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Scanner ────────────────────────────────────────────────
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Camera feed
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: MobileScanner(
                      controller: _controller,
                      onDetect: _onBarcodeDetected,
                    ),
                  ),

                  // Scan frame overlay
                  Container(
                    width: 240,
                    height: 240,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _isProcessing
                            ? const Color(0xFFCCFF00)
                            : const Color(0xFF7B4FD4),
                        width: 3,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),

                  // Corner accents
                  ..._buildCorners(),

                  // Processing indicator
                  if (_isProcessing)
                    Container(
                      width: 240,
                      height: 240,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: Color(0xFFCCFF00)),
                          SizedBox(height: 12),
                          Text('Pairing...',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Torch toggle ───────────────────────────────────────────
            IconButton(
              icon: const Icon(Icons.flashlight_on, color: Colors.white, size: 28),
              onPressed: () => _controller.toggleTorch(),
            ),

            const SizedBox(height: 8),

            // ── Skip ───────────────────────────────────────────────────
            TextButton(
              onPressed: () => Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const PatientHome(patientId: '',)),
                    (route) => false,
              ),
              child: const Text(
                'Skip for now →',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // Corner accent decorations for the scan frame
  List<Widget> _buildCorners() {
    const color = Color(0xFFCCFF00);
    const size = 24.0;
    const thick = 3.0;
    const offset = 108.0; // half of 240 - a little

    return [
      // Top left
      Positioned(
        top: (MediaQuery.of(context).size.height / 2) - offset - 12,
        left: (MediaQuery.of(context).size.width / 2) - offset - 12,
        child: _corner(color, size, thick, top: true, left: true),
      ),
      // Top right
      Positioned(
        top: (MediaQuery.of(context).size.height / 2) - offset - 12,
        right: (MediaQuery.of(context).size.width / 2) - offset - 12,
        child: _corner(color, size, thick, top: true, left: false),
      ),
      // Bottom left
      Positioned(
        bottom: (MediaQuery.of(context).size.height / 2) - offset - 12,
        left: (MediaQuery.of(context).size.width / 2) - offset - 12,
        child: _corner(color, size, thick, top: false, left: true),
      ),
      // Bottom right
      Positioned(
        bottom: (MediaQuery.of(context).size.height / 2) - offset - 12,
        right: (MediaQuery.of(context).size.width / 2) - offset - 12,
        child: _corner(color, size, thick, top: false, left: false),
      ),
    ];
  }

  Widget _corner(Color color, double size, double thick,
      {required bool top, required bool left}) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _CornerPainter(
            color: color, thick: thick, top: top, left: left),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  final Color color;
  final double thick;
  final bool top;
  final bool left;

  _CornerPainter(
      {required this.color,
        required this.thick,
        required this.top,
        required this.left});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thick
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final x = left ? 0.0 : size.width;
    final y = top ? 0.0 : size.height;
    final dx = left ? size.width : -size.width;
    final dy = top ? size.height : -size.height;

    canvas.drawLine(Offset(x, y), Offset(x + dx, y), paint);
    canvas.drawLine(Offset(x, y), Offset(x, y + dy), paint);
  }

  @override
  bool shouldRepaint(_CornerPainter old) => false;
}