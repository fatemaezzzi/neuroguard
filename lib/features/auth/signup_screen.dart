import 'package:flutter/material.dart';
import 'package:neuroguard/core/services/auth_service.dart';
import 'package:neuroguard/features/auth/caregiver_qr_screen.dart';
import 'package:neuroguard/features/auth/patient_scan_screen.dart';
import 'package:neuroguard/features/auth/patient_scan_screen.dart';
import 'package:neuroguard/features/auth/caregiver_qr_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _authService = AuthService();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  String _selectedRole = 'patient';
  bool _isLoading = false;
  String? _error;

  Future<void> _signup() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Please fill in all fields.');
      return;
    }
    if (password.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final uid = await _authService.signUp(
        email: email,
        password: password,
        name: name,
        role: _selectedRole,
      );

      if (!mounted) return;

      // ── Route based on role ──────────────────────────────────────────
      if (_selectedRole == 'caregiver') {
        // Caregiver → show their QR code so the patient can scan it
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => CaregiverQRScreen(
              caregiverId: uid!,
              caregiverName: name,
            ),
          ),
        );
      } else {
        // Patient → show QR scanner so they can scan caregiver's code
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => PatientScanScreen(patientId: uid!),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Back button ───────────────────────────────────────────
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
              ),
              const SizedBox(height: 32),

              // ── Title ─────────────────────────────────────────────────
              const Text(
                'CREATE\nACCOUNT',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Set up your NeuroGuard profile.',
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),

              const SizedBox(height: 36),

              // ── Role toggle ───────────────────────────────────────────
              const Text('I AM A',
                  style: TextStyle(
                      color: Color(0xFFCCFF00),
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      letterSpacing: 1.5)),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  _roleBtn('Patient', 'patient'),
                  _roleBtn('Caregiver', 'caregiver'),
                ]),
              ),

              const SizedBox(height: 28),

              // ── Role hint ─────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF7B4FD4).withOpacity(0.4)),
                ),
                child: Text(
                  _selectedRole == 'caregiver'
                      ? '👤  A QR code will be generated for you after signup. Show it to the patient to link your accounts.'
                      : '📷  After signup you will scan the caregiver\'s QR code to link your accounts.',
                  style: const TextStyle(color: Colors.grey, fontSize: 12, height: 1.5),
                ),
              ),

              const SizedBox(height: 28),

              // ── Name field ────────────────────────────────────────────
              _label('FULL NAME'),
              const SizedBox(height: 8),
              _field(_nameController, 'Enter your name'),

              const SizedBox(height: 18),

              // ── Email field ───────────────────────────────────────────
              _label('EMAIL'),
              const SizedBox(height: 8),
              _field(_emailController, 'Enter your email',
                  keyboard: TextInputType.emailAddress),

              const SizedBox(height: 18),

              // ── Password field ────────────────────────────────────────
              _label('PASSWORD'),
              const SizedBox(height: 8),
              _field(_passwordController, 'Min. 6 characters',
                  obscure: true),

              const SizedBox(height: 12),

              // ── Error ─────────────────────────────────────────────────
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_error!,
                      style: const TextStyle(color: Colors.red, fontSize: 13)),
                ),

              const SizedBox(height: 12),

              // ── Signup button ─────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _signup,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7B4FD4),
                    disabledBackgroundColor:
                    const Color(0xFF7B4FD4).withOpacity(0.5),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5),
                  )
                      : const Text(
                    'CREATE ACCOUNT',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // ── Login link ────────────────────────────────────────────
              Center(
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Text.rich(
                    TextSpan(
                      text: 'Already have an account? ',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                      children: [
                        TextSpan(
                          text: 'Log in',
                          style: TextStyle(
                              color: Color(0xFF7B4FD4),
                              fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roleBtn(String label, String value) => Expanded(
    child: GestureDetector(
      onTap: () => setState(() => _selectedRole = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: _selectedRole == value
              ? const Color(0xFF7B4FD4)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color:
            _selectedRole == value ? Colors.white : Colors.grey,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
    ),
  );

  Widget _label(String text) => Text(
    text,
    style: const TextStyle(
      color: Color(0xFFCCFF00),
      fontWeight: FontWeight.w900,
      fontSize: 12,
      letterSpacing: 1.5,
    ),
  );

  Widget _field(
      TextEditingController controller,
      String hint, {
        bool obscure = false,
        TextInputType keyboard = TextInputType.text,
      }) =>
      TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboard,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.grey),
          filled: true,
          fillColor: const Color(0xFF1A1A1A),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
            const BorderSide(color: Color(0xFF7B4FD4), width: 1.5),
          ),
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      );
}