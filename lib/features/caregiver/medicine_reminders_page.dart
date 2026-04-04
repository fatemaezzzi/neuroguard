import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:neuroguard/core/services/medicine_service.dart';

class MedicineRemindersPage extends StatefulWidget {
  final String patientId;
  const MedicineRemindersPage({super.key, required this.patientId});

  @override
  State<MedicineRemindersPage> createState() => _MedicineRemindersPageState();
}

class _MedicineRemindersPageState extends State<MedicineRemindersPage> {
  final _nameController = TextEditingController();
  TimeOfDay _selectedTime = const TimeOfDay(hour: 8, minute: 0);
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (picked != null && !_disposed) {
      setState(() => _selectedTime = picked);
    }
  }

  Future<void> _addReminder() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    await MedicineService().addReminder(
      patientId: widget.patientId,
      medicineName: name,
      hour: _selectedTime.hour,
      minute: _selectedTime.minute,
    );

    if (!_disposed) {
      _nameController.clear();
      setState(() => _selectedTime = const TimeOfDay(hour: 8, minute: 0));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Medicine reminders')),
      body: Column(
        children: [
          // Add reminder form
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Medicine name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _pickTime,
                        child: Text('Time: ${_selectedTime.format(context)}'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _addReminder,
                      child: const Text('Add'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(),
          // Existing reminders list
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: MedicineService().streamReminders(widget.patientId),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data!.docs;
                if (docs.isEmpty) {
                  return const Center(
                    child: Text('No reminders yet. Add one above.'),
                  );
                }
                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final data = docs[i].data() as Map<String, dynamic>;
                    final hour = data['hour'] as int;
                    final minute = data['minute'] as int;
                    final timeStr =
                        '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
                    return ListTile(
                      leading: const Icon(Icons.medication_outlined),
                      title: Text(data['medicineName'] ?? ''),
                      subtitle: Text(timeStr),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => MedicineService().deleteReminder(
                          patientId: widget.patientId,
                          reminderId: docs[i].id,
                        ),
                      ),
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
}