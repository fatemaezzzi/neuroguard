import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:neuroguard/core/services/medicine_service.dart';

// ─── NeuroGuard design tokens ──────────────────────────────────────────────
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
const _red       = Color(0xFFFF4444);

// Day labels indexed by DateTime.weekday (1=Mon…7=Sun)
const _dayLabels = ['', 'M', 'T', 'W', 'T', 'F', 'S', 'S'];
const _dayFull   = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

class MedicineRemindersPage extends StatefulWidget {
  final String patientId;
  const MedicineRemindersPage({super.key, required this.patientId});

  @override
  State<MedicineRemindersPage> createState() => _MedicineRemindersPageState();
}

class _MedicineRemindersPageState extends State<MedicineRemindersPage> {
  final _nameController         = TextEditingController();
  final _instructionsController = TextEditingController();
  TimeOfDay _selectedTime       = const TimeOfDay(hour: 8, minute: 0);
  List<int> _selectedDays       = [1, 2, 3, 4, 5, 6, 7]; // all days default
  bool _disposed = false;
  bool _adding   = false;

  @override
  void dispose() {
    _disposed = true;
    _nameController.dispose();
    _instructionsController.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: _purple,
            onPrimary: _textPri,
            surface: _card,
            onSurface: _textPri,
          ),
          dialogBackgroundColor: _surface,
        ),
        child: child!,
      ),
    );
    if (picked != null && !_disposed) setState(() => _selectedTime = picked);
  }

  Future<void> _addReminder() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _shake();
      return;
    }
    if (_selectedDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please select at least one day'),
        backgroundColor: _red,
      ));
      return;
    }

    setState(() => _adding = true);
    try {
      await MedicineService().addReminder(
        patientId:    widget.patientId,
        medicineName: name,
        hour:         _selectedTime.hour,
        minute:       _selectedTime.minute,
        instructions: _instructionsController.text.trim(),
        repeatDays:   List<int>.from(_selectedDays)..sort(),
      );
      if (!_disposed) {
        _nameController.clear();
        _instructionsController.clear();
        setState(() {
          _selectedTime = const TimeOfDay(hour: 8, minute: 0);
          _selectedDays = [1, 2, 3, 4, 5, 6, 7];
        });
      }
    } catch (e) {
      if (!_disposed) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to add reminder: $e'),
          backgroundColor: _red,
        ));
      }
    } finally {
      if (!_disposed) setState(() => _adding = false);
    }
  }

  void _shake() {
    // Flash the border red briefly
    setState(() {});
  }

  Future<void> _deleteReminder(String reminderId) async {
    try {
      await MedicineService().deleteReminder(
        patientId:  widget.patientId,
        reminderId: reminderId,
      );
    } catch (e) {
      if (!_disposed) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to delete: $e'),
          backgroundColor: _red,
        ));
      }
    }
  }

  String _formatTime(int hour, int minute) {
    final h    = hour == 0 ? 12 : hour > 12 ? hour - 12 : hour;
    final m    = minute.toString().padLeft(2, '0');
    final ampm = hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ampm';
  }

  String _timeBadge(int hour) {
    if (hour >= 5  && hour < 12) return 'Morning';
    if (hour >= 12 && hour < 17) return 'Afternoon';
    if (hour >= 17 && hour < 21) return 'Evening';
    return 'Night';
  }

  void _toggleDay(int day) {
    setState(() {
      if (_selectedDays.contains(day)) {
        _selectedDays.remove(day);
      } else {
        _selectedDays.add(day);
      }
    });
  }

  // ─── Build ─────────────────────────────────────────────────────────────────
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
          'Medicine Reminders',
          style: TextStyle(
            color: _textPri,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Blob header ──────────────────────────────────────────────────
          _BlobHeader(patientId: widget.patientId),

          // ── Add form ─────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Medicine name
                _darkInput(
                  controller: _nameController,
                  hint: 'Medicine name',
                ),
                const SizedBox(height: 8),

                // Instructions
                _darkInput(
                  controller: _instructionsController,
                  hint: 'Instructions  (e.g. take after food)',
                  icon: Icons.info_outline_rounded,
                ),
                const SizedBox(height: 8),

                // Time + Add
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: _pickTime,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: _card,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: _border, width: 1.5),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.access_time_rounded,
                                  color: _purple, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                _selectedTime.format(context),
                                style: const TextStyle(
                                  color: _purple,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _adding ? null : _addReminder,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 14),
                        decoration: BoxDecoration(
                          color: _adding ? _purpleDim : _purple,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: _adding
                            ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: _textPri),
                        )
                            : const Text(
                          '+ Add',
                          style: TextStyle(
                            color: _textPri,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // ── Day picker ──────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _border, width: 1.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'REPEAT DAYS',
                        style: TextStyle(
                          color: _textMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(7, (i) {
                          final day      = i + 1; // 1=Mon … 7=Sun
                          final selected = _selectedDays.contains(day);
                          return GestureDetector(
                            onTap: () => _toggleDay(day),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: selected ? _purple : _surface,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: selected ? _purple : _border,
                                  width: 1.5,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                _dayLabels[day],
                                style: TextStyle(
                                  color: selected ? _textPri : _textMuted,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Divider + label ───────────────────────────────────────────────
          const Divider(color: _border, height: 1),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Text(
              'YOUR REMINDERS',
              style: TextStyle(
                color: _textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
          ),

          // ── List ──────────────────────────────────────────────────────────
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: MedicineService().streamReminders(widget.patientId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Error loading reminders:\n${snapshot.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: _red, fontSize: 13),
                      ),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(
                      child: CircularProgressIndicator(color: _purple));
                }

                // Client-side sort by hour+minute
                final docs = List<QueryDocumentSnapshot>.from(
                    snapshot.data!.docs)
                  ..sort((a, b) {
                    final ad = a.data() as Map<String, dynamic>;
                    final bd = b.data() as Map<String, dynamic>;
                    return ((ad['hour'] as int? ?? 0) * 60 +
                        (ad['minute'] as int? ?? 0))
                        .compareTo((bd['hour'] as int? ?? 0) * 60 +
                        (bd['minute'] as int? ?? 0));
                  });

                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: _greenDim,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: _green.withOpacity(0.2), width: 1.5),
                          ),
                          child: const Icon(Icons.medication_outlined,
                              color: _green, size: 30),
                        ),
                        const SizedBox(height: 14),
                        const Text('No medicines added yet',
                            style: TextStyle(
                                color: _textSec,
                                fontSize: 15,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        const Text('Add your first reminder above',
                            style: TextStyle(color: _textMuted, fontSize: 13)),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final data = docs[i].data() as Map<String, dynamic>;
                    final hour         = data['hour']         as int?    ?? 8;
                    final minute       = data['minute']       as int?    ?? 0;
                    final name         = data['medicineName'] as String? ?? 'Medicine';
                    final instructions = data['instructions'] as String? ?? '';
                    final repeatDays   = (data['repeatDays']  as List<dynamic>? ??
                        [1, 2, 3, 4, 5, 6, 7])
                        .map((e) => e as int)
                        .toList();

                    return _MedicineCard(
                      name:         name,
                      timeStr:      _formatTime(hour, minute),
                      badge:        _timeBadge(hour),
                      instructions: instructions,
                      repeatDays:   repeatDays,
                      onDelete:     () => _deleteReminder(docs[i].id),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _darkInput({
    required TextEditingController controller,
    required String hint,
    IconData icon = Icons.medication_outlined,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border, width: 1.5),
      ),
      child: TextField(
        controller: controller,
        style: const TextStyle(color: _textPri, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: _textMuted, fontSize: 14),
          border: InputBorder.none,
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }
}

// ─── Blob header ───────────────────────────────────────────────────────────
class _BlobHeader extends StatelessWidget {
  final String patientId;
  const _BlobHeader({required this.patientId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('medicineReminders')
          .doc(patientId)
          .collection('reminders')
          .where('isActive', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        final count = snapshot.data?.docs.length ?? 0;
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          padding: const EdgeInsets.all(18),
          decoration: const BoxDecoration(
            color: _green,
            borderRadius: BorderRadius.only(
              topLeft:     Radius.circular(20),
              topRight:    Radius.circular(20),
              bottomLeft:  Radius.circular(12),
              bottomRight: Radius.circular(40),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("TODAY'S SCHEDULE",
                        style: TextStyle(
                            color: Color(0xFF1A1A1A),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.0)),
                    const SizedBox(height: 4),
                    Text(
                      '$count ${count == 1 ? 'medicine' : 'medicines'}',
                      style: const TextStyle(
                          color: Color(0xFF0A0A0A),
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          height: 1),
                    ),
                    const SizedBox(height: 2),
                    const Text('Stay on track with doses',
                        style:
                        TextStyle(color: Color(0xFF2A2A2A), fontSize: 12)),
                  ],
                ),
              ),
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.medication_rounded,
                    color: Color(0xFF0A0A0A), size: 26),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Medicine card ─────────────────────────────────────────────────────────
class _MedicineCard extends StatelessWidget {
  final String        name;
  final String        timeStr;
  final String        badge;
  final String        instructions;
  final List<int>     repeatDays;
  final VoidCallback  onDelete;

  const _MedicineCard({
    required this.name,
    required this.timeStr,
    required this.badge,
    required this.instructions,
    required this.repeatDays,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final hasInstructions = instructions.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top row ──────────────────────────────────────────────────────
          Row(
            children: [
              // Icon
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _purpleDim,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: _purple.withOpacity(0.3), width: 1.5),
                ),
                child: const Icon(Icons.medication_outlined,
                    color: _purple, size: 22),
              ),
              const SizedBox(width: 12),
              // Name + time
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(
                            color: _textPri,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.access_time_rounded,
                            color: _purple, size: 13),
                        const SizedBox(width: 4),
                        Text(timeStr,
                            style: const TextStyle(
                                color: _purple,
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                ),
              ),
              // Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _greenDim,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: _green.withOpacity(0.25), width: 1),
                ),
                child: Text(badge,
                    style: const TextStyle(
                        color: _green,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
              // Delete
              GestureDetector(
                onTap: onDelete,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _border),
                  ),
                  child:
                  const Icon(Icons.close_rounded, color: _red, size: 16),
                ),
              ),
            ],
          ),

          // ── Instructions row ─────────────────────────────────────────────
          if (hasInstructions) ...[
            const SizedBox(height: 10),
            Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded,
                      color: _textMuted, size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      instructions,
                      style: const TextStyle(
                          color: _textSec, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ── Repeat days row ───────────────────────────────────────────────
          const SizedBox(height: 10),
          Row(
            children: List.generate(7, (i) {
              final day      = i + 1;
              final active   = repeatDays.contains(day);
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