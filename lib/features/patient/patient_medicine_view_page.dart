import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ─── Design tokens ──────────────────────────────────────────────────────────
const _bg        = Color(0xFF0A0A0A);
const _surface   = Color(0xFF111111);
const _card      = Color(0xFF161616);
const _purple    = Color(0xFF7C3AED);
const _purpleDim = Color(0x337C3AED);
const _green     = Color(0xFFADFF2F);
const _greenDim  = Color(0x22ADFF2F);
const _border    = Color(0xFF222222);
const _textPri   = Color(0xFFFFFFFF);
const _textSec   = Color(0xFF888888);
const _textMuted = Color(0xFF444444);
const _orange    = Color(0xFFFF8C00);

const _dayLabels = ['', 'M', 'T', 'W', 'T', 'F', 'S', 'S'];

/// PatientMedicineViewPage
/// ───────────────────────
/// READ-ONLY view for the patient. Caregivers set the reminders; this page
/// just fetches them from Firestore and shows what's scheduled, with a
/// prominent "NEXT UP" strip at the top.
class PatientMedicineViewPage extends StatelessWidget {
  final String patientId;
  const PatientMedicineViewPage({super.key, required this.patientId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        leading: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _border),
            ),
            child: const Icon(Icons.arrow_back, color: _textPri, size: 18),
          ),
        ),
        title: const Text(
          'My Medicines',
          style: TextStyle(
            color: _textPri,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('medicineReminders')
            .doc(patientId)
            .collection('reminders')
            .where('isActive', isEqualTo: true)
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: _purple),
            );
          }

          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.medication_outlined,
                      color: _textMuted, size: 56),
                  const SizedBox(height: 16),
                  const Text(
                    'No medicines scheduled yet',
                    style: TextStyle(
                        color: _textSec,
                        fontSize: 16,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Your caregiver will add reminders here.',
                    style: TextStyle(color: _textMuted, fontSize: 13),
                  ),
                ],
              ),
            );
          }

          // Build reminder list sorted by time
          final reminders = docs.map((doc) {
            final d = doc.data()! as Map<String, dynamic>;
            return _Reminder(
              id:           doc.id,
              name:         d['medicineName'] as String? ?? 'Medicine',
              hour:         d['hour']         as int?    ?? 8,
              minute:       d['minute']       as int?    ?? 0,
              instructions: d['instructions'] as String? ?? '',
              repeatDays:   (d['repeatDays']  as List<dynamic>? ?? [1,2,3,4,5,6,7])
                  .map((e) => e as int)
                  .toList(),
            );
          }).toList()
            ..sort((a, b) => (a.hour * 60 + a.minute)
                .compareTo(b.hour * 60 + b.minute));

          final now      = DateTime.now();
          final nowMins  = now.hour * 60 + now.minute;
          final today    = now.weekday;

          // Find next upcoming for today
          final todayReminders = reminders
              .where((r) => r.repeatDays.contains(today))
              .toList();
          final _Reminder? next = todayReminders.firstWhere(
                (r) => r.mins >= nowMins,
            orElse: () => todayReminders.isNotEmpty ? todayReminders.first : reminders.first,
          );

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              // ── "Next Up" hero strip ──────────────────────────────────────
              if (next != null) _NextUpCard(reminder: next, nowMins: nowMins),
              const SizedBox(height: 20),

              // ── Section label ─────────────────────────────────────────────
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text(
                  'ALL SCHEDULED MEDICINES',
                  style: TextStyle(
                    color: _textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ),

              // ── Medicine cards ─────────────────────────────────────────────
              ...reminders.map(
                    (r) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _PatientMedicineCard(reminder: r, nowMins: nowMins, today: today),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─── "Next Up" hero card ────────────────────────────────────────────────────
class _NextUpCard extends StatelessWidget {
  final _Reminder reminder;
  final int nowMins;
  const _NextUpCard({required this.reminder, required this.nowMins});

  @override
  Widget build(BuildContext context) {
    final isSoon = reminder.mins >= nowMins && reminder.mins - nowMins <= 30;
    final badgeLabel = isSoon ? '${reminder.label} – SOON' : reminder.label.toUpperCase();
    final badgeColor = isSoon ? _orange : _purple;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _purple.withOpacity(0.25), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: _purple.withOpacity(0.15),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                "Today's Reminder",
                style: TextStyle(
                    color: _textSec,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                      letterSpacing: 0.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: _purpleDim,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _purple.withOpacity(0.3), width: 1.5),
                ),
                child: Icon(
                  Icons.medication_rounded,
                  color: isSoon ? _orange : _purple,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reminder.name,
                      style: TextStyle(
                        color: isSoon ? _orange : _textPri,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.access_time_rounded,
                            color: isSoon ? _orange : _purple, size: 15),
                        const SizedBox(width: 4),
                        Text(
                          reminder.timeStr,
                          style: TextStyle(
                            color: isSoon ? _orange : _purple,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (reminder.instructions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, color: _textMuted, size: 14),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      reminder.instructions,
                      style: const TextStyle(color: _textSec, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Individual medicine card (read-only) ───────────────────────────────────
class _PatientMedicineCard extends StatelessWidget {
  final _Reminder reminder;
  final int nowMins;
  final int today;
  const _PatientMedicineCard({
    required this.reminder,
    required this.nowMins,
    required this.today,
  });

  @override
  Widget build(BuildContext context) {
    final isToday  = reminder.repeatDays.contains(today);
    final isUpNext = isToday && reminder.mins >= nowMins && reminder.mins - nowMins <= 60;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isUpNext ? _purple.withOpacity(0.4) : _border,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _purpleDim,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _purple.withOpacity(0.3), width: 1.5),
                ),
                child: const Icon(Icons.medication_outlined, color: _purple, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(reminder.name,
                        style: const TextStyle(
                            color: _textPri,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Row(children: [
                      const Icon(Icons.access_time_rounded, color: _purple, size: 13),
                      const SizedBox(width: 4),
                      Text(reminder.timeStr,
                          style: const TextStyle(
                              color: _purple,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                    ]),
                  ],
                ),
              ),
              // Badge: time-of-day label
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _greenDim,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _green.withOpacity(0.25), width: 1),
                ),
                child: Text(
                  reminder.label,
                  style: const TextStyle(
                      color: _green, fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),

          if (reminder.instructions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _border),
              ),
              child: Row(children: [
                const Icon(Icons.info_outline_rounded, color: _textMuted, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(reminder.instructions,
                      style: const TextStyle(color: _textSec, fontSize: 12)),
                ),
              ]),
            ),
          ],

          // Repeat-day pills (read-only, non-interactive)
          const SizedBox(height: 10),
          Row(
            children: List.generate(7, (i) {
              final day    = i + 1;
              final active = reminder.repeatDays.contains(day);
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: active ? _purpleDim : _surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: active ? _purple.withOpacity(0.5) : _border),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _dayLabels[day],
                    style: TextStyle(
                      color: active ? _purple : _textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

// ─── Data model ─────────────────────────────────────────────────────────────
class _Reminder {
  final String  id;
  final String  name;
  final int     hour;
  final int     minute;
  final String  instructions;
  final List<int> repeatDays;

  const _Reminder({
    required this.id,
    required this.name,
    required this.hour,
    required this.minute,
    required this.instructions,
    required this.repeatDays,
  });

  int get mins => hour * 60 + minute;

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