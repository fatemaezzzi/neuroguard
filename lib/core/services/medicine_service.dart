import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import '../models/alert_model.dart';
import 'alert_service.dart';

/// MedicineService
/// ───────────────
/// • Stores reminders in Firestore under medicineReminders/{patientId}/reminders
/// • Schedules daily local notifications on the CAREGIVER device at the exact time
/// • When a notification fires it also sends an FCM alert to the caregiver via AlertService
/// • Patient device gets a separate local notification (fired by the same scheduled alarm)

class MedicineService {
  static final MedicineService _instance = MedicineService._();
  factory MedicineService() => _instance;
  MedicineService._();

  final _db = FirebaseFirestore.instance;
  final _notifications = FlutterLocalNotificationsPlugin();

  bool _initialised = false;

  static const String _channelId   = 'medicine_reminders';
  static const String _channelName = 'Medicine Reminders';

  // ─── Initialise ────────────────────────────────────────────────────────────
  // Call once from main() or PatientHome/CaregiverHome initState
  Future<void> initialise() async {
    if (_initialised) return;
    _initialised = true;

    // 1. Time-zone DB (required for zonedSchedule)
    tz.initializeTimeZones();
    final timezoneInfo = await FlutterTimezone.getLocalTimezone();
    final String localTz = timezoneInfo.identifier;
    tz.setLocalLocation(tz.getLocation(localTz));

    // 2. Android notification channel
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: 'Reminders to give medication to the patient',
      importance: Importance.high,
    );
    await _notifications
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // 3. Plugin init + tap handler
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );
  }

  // Fired when the user taps a notification while app is open/background
  void _onNotificationTap(NotificationResponse response) {
    // payload format: "patientId|medicineName"
    final parts = (response.payload ?? '').split('|');
    if (parts.length < 2) return;
    final patientId    = parts[0];
    final medicineName = parts[1];
    // Send FCM to caregiver when notification is tapped
    onReminderFired(patientId: patientId, medicineName: medicineName);
  }

  // ─── Add Reminder ──────────────────────────────────────────────────────────
  Future<void> addReminder({
    required String patientId,
    required String medicineName,
    required int    hour,
    required int    minute,
    String? notes,
    List<int> repeatDays = const [1, 2, 3, 4, 5, 6, 7], // 1=Mon … 7=Sun
  }) async {
    // Save to Firestore
    final ref = await _db
        .collection('medicineReminders')
        .doc(patientId)
        .collection('reminders')
        .add({
      'medicineName': medicineName,
      'hour':         hour,
      'minute':       minute,
      'notes':        notes ?? '',
      'isActive':     true,
      'repeatDays':   repeatDays,
      'createdAt':    FieldValue.serverTimestamp(),
    });

    // Schedule local notification using Firestore doc ID as notification ID
    final notifId = ref.id.hashCode.abs() % 100000;
    await _scheduleDaily(
      notifId:       notifId,
      medicineName:  medicineName,
      patientId:     patientId,
      hour:          hour,
      minute:        minute,
    );

    // Store notifId back so we can cancel it on delete
    await ref.update({'notifId': notifId});
  }

  // ─── Delete Reminder ───────────────────────────────────────────────────────
  Future<void> deleteReminder({
    required String patientId,
    required String reminderId,
  }) async {
    final doc = await _db
        .collection('medicineReminders')
        .doc(patientId)
        .collection('reminders')
        .doc(reminderId)
        .get();

    // Cancel the scheduled notification
    final notifId = doc.data()?['notifId'] as int?;
    if (notifId != null) await _notifications.cancel(notifId);

    await doc.reference.delete();
  }

  // ─── Stream Reminders ──────────────────────────────────────────────────────
  Stream<QuerySnapshot> streamReminders(String patientId) {
    return _db
        .collection('medicineReminders')
        .doc(patientId)
        .collection('reminders')
        .where('isActive', isEqualTo: true)
        .orderBy('hour')
        .snapshots();
  }

  // ─── Reschedule All (call after app restart) ───────────────────────────────
  // Ensures alarms survive app kill/reinstall
  Future<void> rescheduleAll(String patientId) async {
    final snap = await _db
        .collection('medicineReminders')
        .doc(patientId)
        .collection('reminders')
        .where('isActive', isEqualTo: true)
        .get();

    for (final doc in snap.docs) {
      final data       = doc.data();
      final notifId    = data['notifId']      as int?    ?? doc.id.hashCode.abs() % 100000;
      final medicine   = data['medicineName'] as String? ?? 'Medicine';
      final hour       = data['hour']         as int?    ?? 8;
      final minute     = data['minute']       as int?    ?? 0;

      await _scheduleDaily(
        notifId:      notifId,
        medicineName: medicine,
        patientId:    patientId,
        hour:         hour,
        minute:       minute,
      );
    }
  }

  // ─── Schedule Daily Local Notification ────────────────────────────────────
  Future<void> _scheduleDaily({
    required int    notifId,
    required String medicineName,
    required String patientId,
    required int    hour,
    required int    minute,
  }) async {
    final now      = tz.TZDateTime.now(tz.local);
    var   scheduled = tz.TZDateTime(
      tz.local, now.year, now.month, now.day, hour, minute,
    );
    // If time already passed today, schedule for tomorrow
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    await _notifications.zonedSchedule(
      notifId,
      'Medicine Reminder',
      'Time to give $medicineName',
      scheduled,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.high,
          priority: Priority.high,
          channelShowBadge: true,
        ),
      ),
      uiLocalNotificationDateInterpretation:
      UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,

      // repeats daily
      matchDateTimeComponents: DateTimeComponents.time,

      payload: '$patientId|$medicineName',
    );
  }

  // ─── Called when alarm fires ───────────────────────────────────────────────
  // Sends FCM push to caregiver via AlertService
  Future<void> onReminderFired({
    required String patientId,
    required String medicineName,
  }) async {
    await AlertService().send(
      patientId: patientId,
      alert: AlertModel(
        type:     AlertType.medicine,
        message:  'Time for $medicineName.',
        severity: AlertSeverity.info,
        metadata: {'medicineName': medicineName},
      ),
    );
  }
}