import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:neuroguard/core/services/pocket_check_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PATIENT-SIDE WIDGET
// Place this widget high in the patient app's widget tree (e.g. inside the
// root Scaffold or a persistent overlay). It owns the PocketCheckService
// lifecycle — initializing the Firestore command listener and the passive
// inactivity monitor — without rendering any visible UI.
//
// Usage (patient app):
//   PocketCheckInitializer(patientId: currentUser.uid, child: MyApp())
// ─────────────────────────────────────────────────────────────────────────────
class PocketCheckInitializer extends StatefulWidget {
  final String patientId;
  final Widget child;

  const PocketCheckInitializer({
    super.key,
    required this.patientId,
    required this.child,
  });

  @override
  State<PocketCheckInitializer> createState() => _PocketCheckInitializerState();
}

class _PocketCheckInitializerState extends State<PocketCheckInitializer> {
  late final PocketCheckService _service;

  @override
  void initState() {
    super.initState();
    // Spin up the service on the patient device.
    // This starts:
    //  • _listenForCaregiverCommand() — watches Firestore for the caregiver trigger flag
    //  • _startPassiveInactivityMonitor() — periodic background variance check
    _service = PocketCheckService(patientId: widget.patientId);
    _service.initialize();
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ─────────────────────────────────────────────────────────────────────────────
// CAREGIVER-SIDE CARD
// Displays the real-time pocket status streamed from Firestore and provides
// a button to remotely trigger an active check on the patient's device.
// ─────────────────────────────────────────────────────────────────────────────
class PocketCheckCard extends StatefulWidget {
  final String patientId;
  const PocketCheckCard({super.key, required this.patientId});

  @override
  State<PocketCheckCard> createState() => _PocketCheckCardState();
}

class _PocketCheckCardState extends State<PocketCheckCard> {
  String _status = 'UNKNOWN';
  String _lastCheckTime = '--:--';

  // _isChecking drives the button lock-out. It is set to true immediately when
  // the caregiver taps the button, then reset to false once Firestore confirms
  // the patient device has finished and written a non-CHECKING status back.
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
        final newStatus = sensors['pocket_status']?.toString() ?? 'UNKNOWN';

        setState(() {
          _status = newStatus;

          final ts = sensors['pocket_check_timestamp'];
          if (ts != null && ts is Timestamp) {
            final dt = ts.toDate();
            _lastCheckTime =
            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
          }

          // FIX: reset _isChecking when Firestore confirms the check has
          // completed (any status other than CHECKING). Previously _isChecking
          // was set to true locally on button press but never set back to false
          // from the stream — it only tracked status == 'CHECKING', which
          // correctly kept the button locked during the check, but this is now
          // made explicit and symmetrical so the button always re-enables after
          // the patient device writes its result.
          _isChecking = newStatus == 'CHECKING';
        });
      }
    });
  }

  // Caregiver presses this to trigger a remote pocket check on the patient device.
  // Sets the Firestore flag that PocketCheckService._listenForCaregiverCommand()
  // is watching, which causes the patient's phone to vibrate and run the
  // accelerometer analysis.
  Future<void> _triggerCheck() async {
    if (_isChecking) return;
    // Optimistically lock the button before the Firestore round-trip confirms.
    setState(() => _isChecking = true);
    await PocketCheckService.triggerRemoteCheck(widget.patientId);
    // _isChecking will be corrected by _listenToStatus() once the patient
    // device writes CHECKING → result back to Firestore.
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
                // Trigger button (caregiver side) — disabled while a check is in flight
                GestureDetector(
                  onTap: _isChecking ? null : _triggerCheck,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(_isChecking ? 0.08 : 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _isChecking ? Icons.hourglass_top : Icons.arrow_outward,
                      color: Colors.white.withOpacity(_isChecking ? 0.4 : 1.0),
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