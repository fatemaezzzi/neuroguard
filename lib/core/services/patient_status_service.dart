import 'package:cloud_firestore/cloud_firestore.dart';

class PatientStatusService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String patientId;

  PatientStatusService({required this.patientId});

  // Last 10 windows for bar graphs and line chart
  Stream<List<Map<String, dynamic>>> get windowsStream => _db
      .collection('sleepSessions')
      .doc(patientId)
      .collection('windows')
      .orderBy('epochTimestamp', descending: true)
      .limit(10)
      .snapshots()
      .map((snap) => snap.docs
      .map((d) => d.data())
      .toList()
      .reversed
      .toList());

  // Today's daily summary
  Stream<Map<String, dynamic>> get todaySummaryStream {
    String today = DateTime.now().toIso8601String().split('T')[0];
    return _db
        .collection('sleepSessions')
        .doc(patientId)
        .collection('dailySummaries')
        .doc(today)
        .snapshots()
        .map((snap) => snap.data() ?? {});
  }

  // Clear location flag after Flutter handles it
  Future<void> clearLocationFlag() async {
    await _db
        .collection('users')
        .doc(patientId)
        .update({'sensors.checkLocationNow': false});
  }
}