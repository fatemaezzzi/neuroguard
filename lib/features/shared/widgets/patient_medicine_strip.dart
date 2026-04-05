import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ─── Design tokens (matches patient_home.dart) ─────────────────────────────
const _purple    = Color(0xFF7B52D9);
const _limeGreen = Color(0xFFB5E800);
const _darkBg    = Color(0xFF1A1A1A);
const _card      = Color(0xFF242424);
const _orange    = Color(0xFFFF8C00);

/// PatientMedicineStrip
/// ────────────────────
/// Reads medicine reminders for [patientId] from Firestore in real-time and
/// displays a strip showing the NEXT upcoming dose today (or the earliest
/// reminder if none are upcoming). Tapping the strip opens the read-only
/// patient medicine view.
///
/// The caregiver has already set the reminders — the patient only sees them.
class PatientMedicineStrip extends StatelessWidget {
  final String patientId;
  final VoidCallback? onTap;

  const PatientMedicineStrip({
    super.key,
    required this.patientId,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('medicineReminders')
          .doc(patientId)
          .collection('reminders')
          .where('isActive', isEqualTo: true)
          .snapshots(),
      builder: (context, snap) {
        // ── Loading ──────────────────────────────────────────────────────────
        if (snap.connectionState == ConnectionState.waiting) {
          return _StripShell(onTap: onTap, child: _loadingContent());
        }

        final docs = snap.data?.docs ?? [];

        // ── No reminders ────────────────────────────────────────────────────
        if (docs.isEmpty) {
          return _StripShell(
            onTap: onTap,
            child: _emptyContent(),
          );
        }

        // ── Find next upcoming dose ──────────────────────────────────────────
        final now     = DateTime.now();
        final nowMins = now.hour * 60 + now.minute;
        final today   = now.weekday; // 1=Mon … 7=Sun

        // Build list of (minutesSinceMidnight, name, instructions) for today
        final todayReminders = <_ReminderSlot>[];
        for (final doc in docs) {
          final data       = doc.data()! as Map<String, dynamic>;
          final hour       = data['hour']         as int? ?? 8;
          final minute     = data['minute']       as int? ?? 0;
          final name       = data['medicineName'] as String? ?? 'Medicine';
          final instruct   = data['instructions'] as String? ?? '';
          final repeatDays = (data['repeatDays']  as List<dynamic>? ?? [1,2,3,4,5,6,7])
              .map((e) => e as int)
              .toList();

          if (repeatDays.contains(today)) {
            todayReminders.add(_ReminderSlot(
              mins:         hour * 60 + minute,
              name:         name,
              instructions: instruct,
              hour:         hour,
              minute:       minute,
            ));
          }
        }

        // Sort by time
        todayReminders.sort((a, b) => a.mins.compareTo(b.mins));

        // Pick next upcoming (>= now), fall back to first of day
        _ReminderSlot? next = todayReminders.firstWhere(
              (r) => r.mins >= nowMins,
          orElse: () => todayReminders.isNotEmpty ? todayReminders.first : _ReminderSlot.empty(),
        );

        if (next.name.isEmpty) {
          // No reminders today — fall back to first reminder overall
          final first = docs.first.data()! as Map<String, dynamic>;
          next = _ReminderSlot(
            mins:         (first['hour'] as int? ?? 8) * 60 + (first['minute'] as int? ?? 0),
            name:         first['medicineName'] as String? ?? 'Medicine',
            instructions: first['instructions'] as String? ?? '',
            hour:         first['hour'] as int? ?? 8,
            minute:       first['minute'] as int? ?? 0,
          );
        }

        final isSoon = next.mins >= nowMins && next.mins - nowMins <= 30;
        final isPast = next.mins < nowMins;

        return _StripShell(
          onTap: onTap,
          child: _reminderContent(
            slot:   next,
            isSoon: isSoon,
            isPast: isPast,
            total:  docs.length,
          ),
        );
      },
    );
  }

  // ── Content builders ───────────────────────────────────────────────────────

  Widget _loadingContent() {
    return const Row(
      children: [
        Icon(Icons.access_time_rounded, color: Colors.white54, size: 22),
        SizedBox(width: 10),
        Text(
          'Loading reminders…',
          style: TextStyle(color: Colors.white54, fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _emptyContent() {
    return const Row(
      children: [
        Icon(Icons.medication_outlined, color: Colors.white38, size: 22),
        SizedBox(width: 10),
        Text(
          'No medicines scheduled',
          style: TextStyle(color: Colors.white38, fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _reminderContent({
    required _ReminderSlot slot,
    required bool isSoon,
    required bool isPast,
    required int total,
  }) {
    // Badge label + colour
    final String badgeLabel;
    final Color  badgeColor;
    if (isPast) {
      badgeLabel = 'NEXT UP';
      badgeColor = _purple;
    } else if (isSoon) {
      badgeLabel = '${slot.label} – SOON';
      badgeColor = _orange;
    } else {
      badgeLabel = slot.label.toUpperCase();
      badgeColor = _purple;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Header row: "Today's Reminder" + badge ─────────────────────────
        Row(
          children: [
            Text(
              "Today's Reminder",
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: badgeColor,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                badgeLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const Spacer(),
            if (total > 1)
              Text(
                '+${total - 1} more',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.45),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),

        // ── Main reminder line ─────────────────────────────────────────────
        Row(
          children: [
            Icon(
              Icons.access_time_rounded,
              color: isSoon ? _orange : Colors.white70,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${slot.name.toUpperCase()}  •  ${slot.timeStr}',
                style: TextStyle(
                  color: isSoon ? _orange : Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),

        // ── Instructions (if any) ──────────────────────────────────────────
        if (slot.instructions.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            slot.instructions,
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}

// ─── Shell container for the strip ─────────────────────────────────────────
class _StripShell extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _StripShell({required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.08), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: _purple.withOpacity(0.12),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

// ─── Data class ─────────────────────────────────────────────────────────────
class _ReminderSlot {
  final int    mins;
  final String name;
  final String instructions;
  final int    hour;
  final int    minute;

  const _ReminderSlot({
    required this.mins,
    required this.name,
    required this.instructions,
    required this.hour,
    required this.minute,
  });

  factory _ReminderSlot.empty() => const _ReminderSlot(
    mins: 0, name: '', instructions: '', hour: 0, minute: 0,
  );

  String get timeStr {
    final h    = hour == 0 ? 12 : hour > 12 ? hour - 12 : hour;
    final m    = minute.toString().padLeft(2, '0');
    final ampm = hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ampm';
  }

  String get label {
    if (hour >= 5  && hour < 12) return 'Morning';
    if (hour >= 12 && hour < 17) return 'Afternoon';
    if (hour >= 17 && hour < 21) return 'Evening';
    return 'Night';
  }
}