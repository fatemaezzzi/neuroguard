import 'package:flutter/material.dart';
import 'package:neuroguard/features/patient/patient_home.dart';

class PatientScanScreen extends StatelessWidget {
  final String patientId;
  const PatientScanScreen({super.key, required this.patientId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('QR Scanner', style: TextStyle(color: Colors.white, fontSize: 24)),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const PatientHome()),
                    (route) => false,
              ),
              child: const Text('Skip for now'),
            ),
          ],
        ),
      ),
    );
  }
}