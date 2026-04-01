import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:convert';
import 'package:neuroguard/features/caregiver/caregiver_home.dart';

// Shown to the caregiver RIGHT AFTER signup.
// They show this screen to the patient who then scans it.
class CaregiverQRScreen extends StatelessWidget {
  final String caregiverId;
  final String caregiverName;

  const CaregiverQRScreen({
    super.key,
    required this.caregiverId,
    required this.caregiverName,
  });

  // QR data: a JSON string containing the caregiver's uid and a type tag
  // so the scanner knows what it's reading.
  String get _qrData => jsonEncode({
    'type': 'neuroguard_pairing',
    'caregiver_id': caregiverId,
    'caregiver_name': caregiverName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ── Header ───────────────────────────────────────────────
              const SizedBox(height: 20),
              const Text(
                'YOUR PAIRING CODE',
                style: TextStyle(
                  color: Color(0xFFCCFF00),
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Show this QR code to the patient.\nThey will scan it to link your accounts.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 40),

              // ── QR Code ───────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF7B4FD4).withOpacity(0.4),
                      blurRadius: 30,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: QrImageView(
                  data: _qrData,
                  version: QrVersions.auto,
                  size: 240,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Color(0xFF7B4FD4),
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Colors.black,
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // ── Caregiver name pill ───────────────────────────────────
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF7B4FD4), width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.person, color: Color(0xFF7B4FD4), size: 20),
                    const SizedBox(width: 8),
                    Text(
                      caregiverName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // ── ID pill ───────────────────────────────────────────────
              Text(
                'ID: $caregiverId',
                style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 11,
                  letterSpacing: 0.5,
                ),
              ),

              const Spacer(),

              // ── Instructions ──────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Column(
                  children: [
                    Row(children: [
                      Text('1.  ', style: TextStyle(color: Color(0xFFCCFF00), fontWeight: FontWeight.bold)),
                      Expanded(child: Text('Open the NeuroGuard app on the patient\'s phone', style: TextStyle(color: Colors.white, fontSize: 13))),
                    ]),
                    SizedBox(height: 8),
                    Row(children: [
                      Text('2.  ', style: TextStyle(color: Color(0xFFCCFF00), fontWeight: FontWeight.bold)),
                      Expanded(child: Text('Patient signs up and reaches the Scan screen', style: TextStyle(color: Colors.white, fontSize: 13))),
                    ]),
                    SizedBox(height: 8),
                    Row(children: [
                      Text('3.  ', style: TextStyle(color: Color(0xFFCCFF00), fontWeight: FontWeight.bold)),
                      Expanded(child: Text('Patient points their camera at this QR code', style: TextStyle(color: Colors.white, fontSize: 13))),
                    ]),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── Skip button (if patient already paired separately) ─────
              TextButton(
                onPressed: () => Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const CaregiverHomePage()),
                      (route) => false,
                ),
                child: const Text(
                  'Skip for now →',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}