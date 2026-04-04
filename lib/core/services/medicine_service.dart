import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/alert_model.dart';
import 'alert_service.dart';

/// Stores medicine schedules in Firestore and schedules local notifications.
/// When a notification fires and the app is open, it also calls AlertService
/// so the caregiver gets an FCM push.
class MedicineService {
  static final MedicineService _instance = MedicineService._();
  factory MedicineService() => _instance;
  MedicineService._();

  final _db = FirebaseFirestore.instance;
  final _notifications = FlutterLocalNotificationsPlugin();

  static const String _channelId = 'medicine_reminders';
  static const String _channelName = 'Medicine Reminders';

  Future<void> initialise() async {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: 'Reminders to give medication to the patient',
      importance: Importance.high,
    );
    await _notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _notifications.initialize(settings);
  }

  /// Save a new reminder to Firestore.
  /// [hour] and [minute] are in 24h format.
  Future<void> addReminder({
    required String patientId,
    required String medicineName,
    required int hour,
    required int minute,
    String? notes,
  }) async {
    await _db
        .collection('medicineReminders')
        .doc(patientId)
        .collection('reminders')
        .add({
      'medicineName': medicineName,
      'hour': hour,
      'minute': minute,
      'notes': notes ?? '',
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteReminder({
    required String patientId,
    required String reminderId,
  }) async {
    await _db
        .collection('medicineReminders')
        .doc(patientId)
        .collection('reminders')
        .doc(reminderId)
        .delete();
  }

  Stream<QuerySnapshot> streamReminders(String patientId) {
    return _db
        .collection('medicineReminders')
        .doc(patientId)
        .collection('reminders')
        .where('isActive', isEqualTo: true)
        .orderBy('hour')
        .snapshots();
  }

  /// Call this when a scheduled notification fires (from notification response).
  /// Writes the alert to Firestore so the caregiver gets an FCM push.
  Future<void> onReminderFired({
    required String patientId,
    required String medicineName,
  }) async {
    await AlertService().send(
      patientId: patientId,
      alert: AlertModel(
        type: AlertType.medicine,
        message: 'Time for $medicineName.',
        severity: AlertSeverity.info,
        metadata: {'medicineName': medicineName},
      ),
    );
  }
}