import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:neuroguard/core/services/auth_service.dart';
import 'package:neuroguard/core/models/escalation_config_model.dart';
import 'package:neuroguard/features/auth/login_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _authService = AuthService();
  final _db = FirebaseFirestore.instance;

  Map<String, dynamic>? _userData;
  String? _linkedName;
  String? _linkedId;         // patientId (used to read/write escalationConfig)
  bool _loading = true;

  // Escalation config state (caregiver only)
  List<SecondaryContact> _contacts = [];
  bool _savingContacts = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final data = await _authService.getUserData();
    String? linkedName;
    String? linkedId;

    if (data != null) {
      final role = data['role'] as String? ?? 'patient';

      if (role == 'caregiver') {
        final patientId = data['paired_patient_id'] as String?;
        if (patientId != null && patientId.isNotEmpty) {
          linkedId = patientId;
          final patientDoc = await _authService.getUserById(patientId);
          linkedName = patientDoc?['name'] as String?;

          // Load escalation config from patient's document
          final raw = patientDoc?['escalationConfig'] as Map<String, dynamic>?;
          if (raw != null) {
            final contacts = ((raw['secondaryContacts'] as List<dynamic>?) ?? [])
                .map((e) => SecondaryContact.fromMap(e as Map<String, dynamic>))
                .toList();
            _contacts = contacts;
          }
        }
      } else {
        final caregiverId = data['paired_caregiver_id'] as String?;
        if (caregiverId != null && caregiverId.isNotEmpty) {
          final caregiverDoc = await _authService.getUserById(caregiverId);
          linkedName = caregiverDoc?['name'] as String?;
        }
      }
    }

    setState(() {
      _userData = data;
      _linkedName = linkedName;
      _linkedId = linkedId;
      _loading = false;
    });
  }

  // ── Escalation contacts CRUD ──────────────────────────────────────────────

  Future<void> _saveContacts() async {
    if (_linkedId == null) return;
    setState(() => _savingContacts = true);
    try {
      await _db.collection('users').doc(_linkedId).set({
        'escalationConfig': {
          'enabled': true,
          'tier1DelaySeconds': 120,
          'tier2DelaySeconds': 300,
          'tier3DelaySeconds': 600,
          'secondaryContacts': _contacts.map((c) => c.toMap()).toList(),
        },
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Emergency contacts saved.'),
            backgroundColor: Color(0xFF7B4FD4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _savingContacts = false);
    }
  }

  void _addContact() {
    _showContactDialog(null, null);
  }

  void _editContact(int index) {
    _showContactDialog(index, _contacts[index]);
  }

  void _deleteContact(int index) {
    setState(() => _contacts.removeAt(index));
  }

  void _showContactDialog(int? editIndex, SecondaryContact? existing) {
    final nameCtrl     = TextEditingController(text: existing?.name ?? '');
    final phoneCtrl    = TextEditingController(text: existing?.phone ?? '');
    final relationCtrl = TextEditingController(text: existing?.relation ?? '');

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          editIndex == null ? 'Add emergency contact' : 'Edit contact',
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dialogField(nameCtrl, 'Name', Icons.person_outline),
            const SizedBox(height: 12),
            _dialogField(phoneCtrl, 'Phone (10 digits)', Icons.phone_outlined,
                type: TextInputType.phone),
            const SizedBox(height: 12),
            _dialogField(relationCtrl, 'Relation (e.g. Daughter)',
                Icons.people_outline),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              final phone = phoneCtrl.text.trim();
              final name  = nameCtrl.text.trim();
              if (name.isEmpty || phone.length < 10) return;

              final contact = SecondaryContact(
                name:     name,
                phone:    phone,
                relation: relationCtrl.text.trim(),
              );

              setState(() {
                if (editIndex == null) {
                  _contacts.add(contact);
                } else {
                  _contacts[editIndex] = contact;
                }
              });
              Navigator.pop(context);
            },
            child: const Text('Save',
                style: TextStyle(
                    color: Color(0xFFCCFF00), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _dialogField(
      TextEditingController ctrl,
      String label,
      IconData icon, {
        TextInputType type = TextInputType.text,
      }) {
    return TextField(
      controller: ctrl,
      keyboardType: type,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey, fontSize: 13),
        prefixIcon: Icon(icon, color: const Color(0xFF7B4FD4), size: 18),
        filled: true,
        fillColor: const Color(0xFF2A2A2A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }

  // ── Logout ────────────────────────────────────────────────────────────────

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Log Out',
            style:
            TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text('Are you sure you want to log out?',
            style: TextStyle(color: Colors.grey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Log Out',
                style: TextStyle(
                    color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    await _authService.signOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final role        = _userData?['role'] as String? ?? 'patient';
    final name        = _userData?['name'] as String? ?? '—';
    final email       = _userData?['email'] as String? ??
        FirebaseAuth.instance.currentUser?.email ?? '—';
    final isPaired    = _userData?['is_paired'] == true;
    final isCaregiver = role == 'caregiver';

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'SETTINGS',
          style: TextStyle(
            color: Color(0xFFCCFF00),
            fontWeight: FontWeight.w900,
            fontSize: 18,
            letterSpacing: 2,
          ),
        ),
      ),
      body: _loading
          ? const Center(
          child:
          CircularProgressIndicator(color: Color(0xFF7B4FD4)))
          : SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
            horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Profile card ────────────────────────────
            _profileCard(name, email, isCaregiver),

            const SizedBox(height: 24),

            // ── Linked account ──────────────────────────
            _sectionLabel('LINKED ACCOUNT'),
            const SizedBox(height: 10),
            _linkedCard(isCaregiver, isPaired),

            // ── Emergency contacts (caregiver only) ─────
            if (isCaregiver && isPaired) ...[
              const SizedBox(height: 32),
              _sectionLabel('EMERGENCY CONTACTS'),
              const SizedBox(height: 6),
              const Text(
                'Added to your patient\'s escalation chain. Notified by SMS if you don\'t respond within 10 minutes.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 12),
              ..._contacts.asMap().entries.map(
                    (e) => _contactTile(e.key, e.value),
              ),
              _addContactButton(),
              if (_contacts.isNotEmpty) ...[
                const SizedBox(height: 12),
                _saveContactsButton(),
              ],
            ],

            const SizedBox(height: 32),

            // ── Logout ──────────────────────────────────
            _logoutButton(),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ── Widget helpers ────────────────────────────────────────────────────────

  Widget _sectionLabel(String text) => Text(
    text,
    style: const TextStyle(
      color: Color(0xFFCCFF00),
      fontWeight: FontWeight.w900,
      fontSize: 12,
      letterSpacing: 1.5,
    ),
  );

  Widget _profileCard(String name, String email, bool isCaregiver) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF7B4FD4), width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                  color: Color(0xFF7B4FD4), shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 20)),
                  const SizedBox(height: 4),
                  Text(email,
                      style: const TextStyle(
                          color: Colors.grey, fontSize: 13)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isCaregiver
                          ? const Color(0xFF7B4FD4)
                          : const Color(0xFF1E3A2F),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isCaregiver ? 'CAREGIVER' : 'PATIENT',
                      style: TextStyle(
                        color: isCaregiver
                            ? Colors.white
                            : const Color(0xFFCCFF00),
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _linkedCard(bool isCaregiver, bool isPaired) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFF1A1A1A),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        Icon(
          isCaregiver
              ? Icons.personal_injury
              : Icons.supervisor_account,
          color: const Color(0xFF7B4FD4),
          size: 28,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isCaregiver ? 'Linked Patient' : 'Linked Caregiver',
                style:
                const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                isPaired && _linkedName != null
                    ? _linkedName!
                    : 'Not paired yet',
                style: TextStyle(
                  color: isPaired && _linkedName != null
                      ? Colors.white
                      : Colors.grey,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isPaired
                ? Colors.green.withOpacity(0.15)
                : Colors.red.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            isPaired ? 'Paired ✓' : 'Unpaired',
            style: TextStyle(
              color: isPaired ? Colors.green : Colors.red,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _contactTile(int index, SecondaryContact contact) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding:
    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: const Color(0xFF1A1A1A),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
          color: const Color(0xFF7B4FD4).withOpacity(0.3)),
    ),
    child: Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFF7B4FD4).withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            contact.name.isNotEmpty
                ? contact.name[0].toUpperCase()
                : '?',
            style: const TextStyle(
                color: Color(0xFF7B4FD4),
                fontWeight: FontWeight.bold,
                fontSize: 14),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(contact.name,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14)),
              const SizedBox(height: 2),
              Text(
                '${contact.phone}  ·  ${contact.relation}',
                style: const TextStyle(
                    color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => _editContact(index),
          icon: const Icon(Icons.edit_outlined,
              color: Colors.grey, size: 18),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: () => _deleteContact(index),
          icon: const Icon(Icons.delete_outline,
              color: Colors.red, size: 18),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ],
    ),
  );

  Widget _addContactButton() => GestureDetector(
    onTap: _addContact,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: const Color(0xFFCCFF00).withOpacity(0.4),
            style: BorderStyle.solid),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add, color: Color(0xFFCCFF00), size: 18),
          SizedBox(width: 6),
          Text('Add contact',
              style: TextStyle(
                  color: Color(0xFFCCFF00),
                  fontWeight: FontWeight.bold,
                  fontSize: 13)),
        ],
      ),
    ),
  );

  Widget _saveContactsButton() => SizedBox(
    width: double.infinity,
    height: 48,
    child: ElevatedButton(
      onPressed: _savingContacts ? null : _saveContacts,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF7B4FD4),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
      ),
      child: _savingContacts
          ? const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
              color: Colors.white, strokeWidth: 2))
          : const Text(
        'SAVE CONTACTS',
        style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 13,
            letterSpacing: 1),
      ),
    ),
  );

  Widget _logoutButton() => SizedBox(
    width: double.infinity,
    height: 56,
    child: ElevatedButton.icon(
      onPressed: _logout,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Colors.red, width: 1.5),
        ),
      ),
      icon: const Icon(Icons.logout, color: Colors.red, size: 20),
      label: const Text(
        'LOG OUT',
        style: TextStyle(
            color: Colors.red,
            fontWeight: FontWeight.w900,
            fontSize: 15,
            letterSpacing: 1),
      ),
    ),
  );
}