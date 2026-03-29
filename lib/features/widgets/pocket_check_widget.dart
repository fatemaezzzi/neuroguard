import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:neuroguard/core/services/pocket_check_service.dart';

class PocketCheckCard extends StatefulWidget {
  final String patientId;
  const PocketCheckCard({super.key, required this.patientId});

  @override
  State<PocketCheckCard> createState() => _PocketCheckCardState();
}

class _PocketCheckCardState extends State<PocketCheckCard> {
  String _status = 'UNKNOWN';
  String _lastCheckTime = '--:--';
  bool _isChecking = false;

  late final DocumentReference _doc;

  @override
  void initState() {
    super.initState();
    _doc = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.patientId);
    _listenToStatus();
  }

  void _listenToStatus() {
    _doc.snapshots().listen((snapshot) {
      if (!snapshot.exists || !mounted) return;

      final data = snapshot.data() as Map<String, dynamic>?;
      final sensors = data?['sensors'] as Map<String, dynamic>?;

      if (sensors != null) {
        setState(() {
          _status = sensors['pocket_status']?.toString() ?? 'UNKNOWN';

          final ts = sensors['pocket_check_timestamp'];
          if (ts != null && ts is Timestamp) {
            final dt = ts.toDate();
            _lastCheckTime =
            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
          }

          _isChecking = _status == 'CHECKING';
        });
      }
    });
  }

  // Caregiver presses this to trigger a remote pocket check
  Future<void> _triggerCheck() async {
    setState(() => _isChecking = true);
    await PocketCheckService.triggerRemoteCheck(widget.patientId);
  }

  Color get _statusColor => switch (_status) {
    'ON_PERSON' => const Color(0xFF7CFC00),  // Green
    'ON_TABLE'  => const Color(0xFFFF4444),  // Red
    'CHECKING'  => const Color(0xFFFFD700),  // Yellow
    _           => const Color(0xFF888888),  // Grey
  };

  IconData get _statusIcon => switch (_status) {
    'ON_PERSON' => Icons.person_outline,
    'ON_TABLE'  => Icons.phone_android,
    'CHECKING'  => Icons.radar,
    _           => Icons.help_outline,
  };

  String get _statusLabel => switch (_status) {
    'ON_PERSON' => 'On Person',
    'ON_TABLE'  => 'Left on Surface',
    'CHECKING'  => 'Checking...',
    _           => 'Unknown',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF7B2FFF),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'POCKET CHECK',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                // Trigger button (caregiver side)
                GestureDetector(
                  onTap: _isChecking ? null : _triggerCheck,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _isChecking ? Icons.hourglass_top : Icons.arrow_outward,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Status Indicator
            Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: _statusColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color: _statusColor.withOpacity(0.6), blurRadius: 8),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Icon(_statusIcon, color: _statusColor, size: 22),
                const SizedBox(width: 8),
                Text(
                  _statusLabel,
                  style: TextStyle(
                    color: _statusColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Last vibration test timestamp
            Text(
              'LAST VIBRATION TEST\n$_lastCheckTime',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.6,
              ),
            ),

            const SizedBox(height: 12),

            // ON/OFF indicator
            Text(
              'ON/OFF PERSON',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 12,
                letterSpacing: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}