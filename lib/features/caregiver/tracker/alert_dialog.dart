import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:neuroguard/core/services/geofence_service.dart';
import 'package:neuroguard/core/services/location_service.dart';

/// alert_dialog.dart
///
/// All alert dialogs used across the NeuroGuard tracker feature, as
/// standalone reusable functions and widget classes:
///
///   1. BreachConfirmationDialog  — "Is this supervised?" sheet
///   2. RedAlertDialog            — Escalated red alert full-screen overlay
///   3. ZoneRestoredDialog        — Patient returned to safe zone banner
///   4. NoZoneSetDialog           — Caregiver hasn't set a zone yet
///   5. LocationStaleDialog       — GPS data is old / stale warning
///   6. PermissionDeniedDialog    — Background location not granted
///
/// Usage examples at the bottom of this file.

// ══════════════════════════════════════════════════════════════════════════════
// SHARED PALETTE
// ══════════════════════════════════════════════════════════════════════════════

class _NG {
  static const Color darkBg  = Color(0xFF0D0D1A);
  static const Color cardBg  = Color(0xFF1A1A2E);
  static const Color purple  = Color(0xFF7B2FBE);
  static const Color green   = Color(0xFF9BFF4F);
  static const Color teal    = Color(0xFF2DD4BF);
  static const Color amber   = Color(0xFFFFB84D);
  static const Color red     = Color(0xFFFF3B3B);
  static const Color white   = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFF141428);
}

// ══════════════════════════════════════════════════════════════════════════════
// 1. BREACH CONFIRMATION DIALOG
// ══════════════════════════════════════════════════════════════════════════════

/// Bottom sheet that appears when the patient leaves the safe zone.
/// Caregiver must actively choose: supervised outing OR escalate to red alert.
///
/// Returns [BreachResponse.supervised] or [BreachResponse.escalate].

enum BreachResponse { supervised, escalate }

class BreachConfirmationSheet extends StatefulWidget {
  final GeofenceEvent event;

  const BreachConfirmationSheet({Key? key, required this.event})
      : super(key: key);

  /// Show the sheet. Returns a [BreachResponse] or null if dismissed.
  static Future<BreachResponse?> show(
      BuildContext context, {
        required GeofenceEvent event,
      }) {
    return showModalBottomSheet<BreachResponse>(
      context: context,
      isDismissible: false,      // Force caregiver to make a decision
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BreachConfirmationSheet(event: event),
    );
  }

  @override
  State<BreachConfirmationSheet> createState() =>
      _BreachConfirmationSheetState();
}

class _BreachConfirmationSheetState extends State<BreachConfirmationSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  // Countdown before auto-escalate (seconds)
  int _countdown = 60;
  late final _countdownTimer = Stream.periodic(
    const Duration(seconds: 1),
        (i) => 59 - i,
  ).take(60);

  @override
  void initState() {
    super.initState();
    HapticFeedback.vibrate();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    )..forward();

    _fadeAnim = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    // Start countdown stream
    _countdownTimer.listen((tick) {
      if (mounted) setState(() => _countdown = tick + 1);
      if (tick == 0 && mounted) {
        // Auto-escalate if no response in 60 seconds
        Navigator.of(context).pop(BreachResponse.escalate);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double distanceOutside = widget.event.distanceFromCenter - widget.event.radiusMeters;
    final String distanceStr = GeofenceService.formatDistance(
        distanceOutside.clamp(0, double.infinity));

    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          decoration: BoxDecoration(
            color: _NG.surface,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: _NG.red.withOpacity(0.6), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: _NG.red.withOpacity(0.2),
                blurRadius: 32,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Alert header ──────────────────────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _AlertIcon(
                      icon: Icons.warning_amber_rounded,
                      color: _NG.red,
                      size: 48,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Safe Zone Breach',
                            style: TextStyle(
                              color: _NG.red,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Patient is $distanceStr outside the safe zone.',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Countdown ring
                    _CountdownRing(countdown: _countdown, total: 60),
                  ],
                ),

                const SizedBox(height: 20),

                // ── Divider ───────────────────────────────────────────────
                Container(height: 1, color: Colors.white10),
                const SizedBox(height: 20),

                // ── Question ──────────────────────────────────────────────
                const Text(
                  'Is this a supervised outing?',
                  style: TextStyle(
                    color: _NG.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Auto-escalating to red alert in $_countdown seconds if no response.',
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),

                const SizedBox(height: 18),

                // ── Action Buttons ────────────────────────────────────────
                Row(
                  children: [
                    // "It's fine" — supervised
                    Expanded(
                      child: _BreachActionButton(
                        label: "It's fine",
                        sublabel: 'Supervised outing',
                        icon: Icons.check_circle_rounded,
                        color: _NG.teal,
                        onTap: () {
                          HapticFeedback.mediumImpact();
                          Navigator.of(context).pop(BreachResponse.supervised);
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    // "Not supervised" — escalate
                    Expanded(
                      child: _BreachActionButton(
                        label: 'Not supervised',
                        sublabel: 'Send red alert',
                        icon: Icons.crisis_alert_rounded,
                        color: _NG.red,
                        onTap: () {
                          HapticFeedback.heavyImpact();
                          Navigator.of(context).pop(BreachResponse.escalate);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────

class _BreachActionButton extends StatelessWidget {
  final String label;
  final String sublabel;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _BreachActionButton({
    required this.label,
    required this.sublabel,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.45), width: 1.5),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    sublabel,
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────

class _CountdownRing extends StatelessWidget {
  final int countdown;
  final int total;
  const _CountdownRing({required this.countdown, required this.total});

  @override
  Widget build(BuildContext context) {
    final double progress = countdown / total;
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: progress,
            strokeWidth: 3,
            backgroundColor: Colors.white12,
            color: progress > 0.4 ? _NG.amber : _NG.red,
          ),
          Text(
            '$countdown',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 2. RED ALERT DIALOG
// ══════════════════════════════════════════════════════════════════════════════

/// Full-screen red alert dialog shown after caregiver taps "Not supervised".
/// Forces caregiver to take an action: Spy Call, View Location, or Dismiss.

class RedAlertDialog extends StatefulWidget {
  final String patientId;
  final String patientName;
  final double distanceMeters;
  final VoidCallback? onSpyCall;
  final VoidCallback? onViewLocation;

  const RedAlertDialog({
    Key? key,
    required this.patientId,
    required this.patientName,
    required this.distanceMeters,
    this.onSpyCall,
    this.onViewLocation,
  }) : super(key: key);

  static Future<void> show(
      BuildContext context, {
        required String patientId,
        required String patientName,
        required double distanceMeters,
        VoidCallback? onSpyCall,
        VoidCallback? onViewLocation,
      }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: _NG.red.withOpacity(0.15),
      builder: (_) => RedAlertDialog(
        patientId: patientId,
        patientName: patientName,
        distanceMeters: distanceMeters,
        onSpyCall: onSpyCall,
        onViewLocation: onViewLocation,
      ),
    );
  }

  @override
  State<RedAlertDialog> createState() => _RedAlertDialogState();
}

class _RedAlertDialogState extends State<RedAlertDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    HapticFeedback.vibrate();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.9, end: 1.1).animate(
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
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _NG.surface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: _NG.red, width: 2),
          boxShadow: [
            BoxShadow(
              color: _NG.red.withOpacity(0.3),
              blurRadius: 40,
              spreadRadius: 8,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Pulsing red icon ────────────────────────────────────────
            AnimatedBuilder(
              animation: _pulseAnim,
              builder: (_, __) => Transform.scale(
                scale: _pulseAnim.value,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: _NG.red.withOpacity(0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: _NG.red, width: 2),
                  ),
                  child: const Icon(
                    Icons.crisis_alert_rounded,
                    color: _NG.red,
                    size: 40,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // ── Title ────────────────────────────────────────────────────
            const Text(
              '🚨  RED ALERT',
              style: TextStyle(
                color: _NG.red,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              '${widget.patientName} is unsupervised\nand outside the safe zone',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                height: 1.5,
              ),
            ),

            const SizedBox(height: 6),

            Text(
              '${GeofenceService.formatDistance(widget.distanceMeters)} from safe zone centre',
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),

            const SizedBox(height: 24),

            // ── Action Buttons ────────────────────────────────────────────
            // Spy Call — primary action
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () {
                  HapticFeedback.heavyImpact();
                  Navigator.of(context).pop();
                  widget.onSpyCall?.call();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _NG.purple,
                  foregroundColor: _NG.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.headset_mic_rounded, size: 20),
                label: const Text(
                  'Open Spy Call',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),
            ),

            const SizedBox(height: 10),

            // View Location button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton.icon(
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  Navigator.of(context).pop();
                  widget.onViewLocation?.call();
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: _NG.white,
                  side: const BorderSide(color: Colors.white24),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.map_rounded, size: 20),
                label: const Text(
                  'View on Map',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),

            const SizedBox(height: 10),

            // Dismiss (small, deemphasised)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Dismiss alert',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 3. ZONE RESTORED DIALOG (Patient returned home)
// ══════════════════════════════════════════════════════════════════════════════

/// Small animated snackbar-style banner when the patient returns to the safe zone.
/// Call [ZoneRestoredBanner.show(context)] — auto-dismisses after 4 seconds.

class ZoneRestoredBanner {
  static void show(BuildContext context, {required String patientName}) {
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.all(12),
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: _NG.teal,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: _NG.teal.withOpacity(0.35),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.home_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$patientName is back home ✅',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Text(
                      'Patient returned to the safe zone',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 4. NO ZONE SET DIALOG
// ══════════════════════════════════════════════════════════════════════════════

/// Shown when caregiver opens tracker but no safe zone has been configured yet.
/// Prompts them to set one now or continue without one.

class NoZoneSetDialog {
  static Future<bool> show(BuildContext context) async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: _NG.cardBg,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _NG.amber.withOpacity(0.4)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _AlertIcon(icon: Icons.location_off_rounded, color: _NG.amber, size: 56),
              const SizedBox(height: 16),
              const Text(
                'No Safe Zone Set',
                style: TextStyle(
                  color: _NG.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'You haven\'t defined a safe zone for this patient yet.\n\n'
                    'Without a safe zone, breach alerts cannot be triggered. '
                    'Would you like to set one now?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 13,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _NG.amber,
                    foregroundColor: Colors.black,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text(
                    'Set Safe Zone Now',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text(
                  'Continue without safe zone',
                  style: TextStyle(color: Colors.white38, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return result ?? false; // true = go to editor, false = skip
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 5. STALE LOCATION DIALOG
// ══════════════════════════════════════════════════════════════════════════════

/// Shown when the patient's last GPS update is older than a threshold.
/// Warns caregiver that location data may be unreliable.

class StaleLocationDialog {
  static Future<void> show(
      BuildContext context, {
        required LocationSnapshot location,
      }) async {
    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: _NG.cardBg,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _NG.amber.withOpacity(0.5)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _AlertIcon(icon: Icons.gps_off_rounded, color: _NG.amber, size: 52),
              const SizedBox(height: 14),
              const Text(
                'Location May Be Outdated',
                style: TextStyle(
                  color: _NG.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Last location update was ${location.minutesAgo} minutes ago. '
                    'The patient\'s phone may be off, out of battery, or in an area with poor GPS signal.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              // Accuracy chip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.access_time_rounded,
                        color: Colors.white38, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      'Last seen ${location.freshnessLabel}  •  ${location.accuracyLabel}',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _NG.amber.withOpacity(0.15),
                    foregroundColor: _NG.amber,
                    elevation: 0,
                    side: const BorderSide(color: _NG.amber),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text(
                    'Understood',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 6. PERMISSION DENIED DIALOG
// ══════════════════════════════════════════════════════════════════════════════

/// Shown when the patient's device has denied background location permission.
/// Guides caregiver on how to fix it and what tracking will still work.

class PermissionDeniedDialog {
  static Future<void> show(
      BuildContext context, {
        required PermissionStatus status,
      }) async {
    final bool isPermanent = status == PermissionStatus.permanentlyDenied;

    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: _NG.cardBg,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _NG.red.withOpacity(0.4)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _AlertIcon(icon: Icons.lock_rounded, color: _NG.red, size: 42),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isPermanent
                              ? 'Location Permanently Blocked'
                              : 'Background Location Needed',
                          style: const TextStyle(
                            color: _NG.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isPermanent
                              ? 'You must enable it in device Settings.'
                              : 'Please allow "All the time" location access.',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),
              Container(height: 1, color: Colors.white10),
              const SizedBox(height: 16),

              // Explain what works vs what doesn't
              _PermissionRow(
                icon: Icons.check_circle_rounded,
                color: _NG.teal,
                text: 'Manual location fetch still works',
              ),
              const SizedBox(height: 8),
              _PermissionRow(
                icon: Icons.cancel_rounded,
                color: _NG.red,
                text: 'Background tracking is disabled',
              ),
              const SizedBox(height: 8),
              _PermissionRow(
                icon: Icons.cancel_rounded,
                color: _NG.red,
                text: 'Safe zone breach alerts won\'t fire',
              ),

              const SizedBox(height: 20),

              if (isPermanent)
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      // In production: openAppSettings() from app_settings package
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _NG.purple,
                      foregroundColor: _NG.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.settings_rounded, size: 18),
                    label: const Text('Open App Settings',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),

              const SizedBox(height: 8),

              Center(
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text(
                    'Continue anyway',
                    style: TextStyle(color: Colors.white38, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _PermissionRow({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 10),
        Text(text, style: const TextStyle(color: Colors.white70, fontSize: 13)),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SHARED WIDGETS
// ══════════════════════════════════════════════════════════════════════════════

class _AlertIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const _AlertIcon({required this.icon, required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        shape: BoxShape.circle,
        border: Border.all(color: color.withOpacity(0.4), width: 1.5),
      ),
      child: Icon(icon, color: color, size: size * 0.48),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// USAGE REFERENCE
// ══════════════════════════════════════════════════════════════════════════════
//
// 1. Breach Confirmation Sheet (in tracker_page.dart):
//
//    final response = await BreachConfirmationSheet.show(
//      context,
//      event: geofenceEvent,
//    );
//    if (response == BreachResponse.supervised) {
//      GeofenceService().acknowledgeBreachAsSafe(patientId);
//    } else if (response == BreachResponse.escalate) {
//      GeofenceService().escalateToRedAlert(patientId);
//    }
//
// 2. Red Alert Dialog (after escalation):
//
//    RedAlertDialog.show(
//      context,
//      patientId: 'patient_01',
//      patientName: 'John Doe',
//      distanceMeters: 450.0,
//      onSpyCall: () => _openSpyCall(),
//      onViewLocation: () => _centerOnPatient(),
//    );
//
// 3. Zone Restored Banner:
//
//    ZoneRestoredBanner.show(context, patientName: 'John Doe');
//
// 4. No Zone Set Dialog (in tracker_page initState):
//
//    final shouldGoToEditor = await NoZoneSetDialog.show(context);
//    if (shouldGoToEditor) _openSafeZoneEditor();
//
// 5. Stale Location Dialog:
//
//    if (location.minutesAgo > 15) {
//      StaleLocationDialog.show(context, location: location);
//    }
//
// 6. Permission Denied Dialog:
//
//    final status = await LocationService().getPermissionStatus();
//    if (status != PermissionStatus.alwaysAllowed) {
//      PermissionDeniedDialog.show(context, status: status);
//    }