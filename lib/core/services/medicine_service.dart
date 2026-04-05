import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import '../../firebase_options.dart';
import '../models/alert_model.dart';
import 'package:firebase_core/firebase_core.dart';
import 'alert_service.dart';

/// MedicineService
/// ───────────────
/// FIXES IN THIS VERSION:
///
/// 1. Asia/Calcutta → Asia/Kolkata alias
///    Some Android devices (especially older Samsung/stock ROMs) return the
///    deprecated IANA name "Asia/Calcutta". The timezone package only ships
///    the canonical name "Asia/Kolkata". We remap known aliases before calling
///    tz.getLocation() so initialise() never throws on Indian devices.
///
/// 2. Silent crash guard on tz.getLocation()
///    Wrapped in try/catch — if the device returns any unrecognised timezone
///    string we fall back to UTC so the app keeps running instead of dying
///    silently with _initialised=true but tz.local unset.
///
/// 3. Alarm reliability on Android 12+
///    • Requests SCHEDULE_EXACT_ALARM permission at runtime.
///    • Requests REQUEST_IGNORE_BATTERY_OPTIMIZATIONS so Doze mode doesn't
///      swallow the alarm.
///    • Uses exactAllowWhileIdle when permitted, inexact as fallback.
///
/// 4. FIX: _onNotificationTap moved to top-level with @pragma('vm:entry-point')
///    so it works as a background notification handler (Flutter requirement).
///
/// 5. FIX: Removed RawResourceAndroidNotificationSound('notification') —
///    the raw resource file did not exist, causing a PlatformException.
///    Now uses the device default notification sound.

// ─── Top-level background notification handler ────────────────────────────────
// MUST be a top-level or static function — Flutter requirement for background
// isolate entry points. Do NOT move this inside the class.
@pragma('vm:entry-point')
Future<void> _onNotificationTap(NotificationResponse response) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
  final parts = (response.payload ?? '').split('|');
  if (parts.length < 2) return;
  await MedicineService().onReminderFired(
    patientId:    parts[0],
    medicineName: parts[1],
  );
}

class MedicineService {
  static final MedicineService _instance = MedicineService._();
  factory MedicineService() => _instance;
  MedicineService._();

  final _db            = FirebaseFirestore.instance;
  final _notifications = FlutterLocalNotificationsPlugin();

  bool _initialised   = false;
  bool _exactAlarmsOk = false;

  static const String _alarmChannelId   = 'medicine_alarm';
  static const String _alarmChannelName = 'Medicine Alarm';

  // ─── Known deprecated IANA timezone aliases ────────────────────────────────
  // Maps what Android may return → canonical IANA name in the tz package.
  static const Map<String, String> _tzAliases = {
    'Asia/Calcutta':    'Asia/Kolkata',
    'Asia/Ulaanbaatar': 'Asia/Ulan_Bator',
    'Asia/Rangoon':     'Asia/Yangon',
    'Asia/Katmandu':    'Asia/Kathmandu',
    'Asia/Dacca':       'Asia/Dhaka',
    'Asia/Saigon':      'Asia/Ho_Chi_Minh',
    'America/Godthab':  'America/Nuuk',
    'Pacific/Truk':     'Pacific/Chuuk',
    'Pacific/Ponape':   'Pacific/Pohnpei',
    'Africa/Asmera':    'Africa/Asmara',
    'Atlantic/Faeroe':  'Atlantic/Faroe',
    'Europe/Kiev':      'Europe/Kyiv',
  };

  // ─── Initialise (idempotent, safe to call multiple times) ─────────────────
  Future<void> initialise() async {
    if (_initialised) return;
    _initialised = true;

    // 1. Timezone — with alias fix + crash guard
    tz.initializeTimeZones();
    try {
      final rawTz     = (await FlutterTimezone.getLocalTimezone()).toString();
      final canonical = _tzAliases[rawTz] ?? rawTz;
      tz.setLocalLocation(tz.getLocation(canonical));
    } catch (_) {
      // Device returned an unrecognised timezone string.
      // Fall back to UTC so scheduling still works (times will be off by the
      // UTC offset, but the app won't crash).
      tz.setLocalLocation(tz.UTC);
    }

    // 2. Request SCHEDULE_EXACT_ALARM (Android 12+ / API 31+)
    try {
      final exactStatus = await Permission.scheduleExactAlarm.status;
      if (!exactStatus.isGranted) {
        final result   = await Permission.scheduleExactAlarm.request();
        _exactAlarmsOk = result.isGranted;
      } else {
        _exactAlarmsOk = true;
      }
    } catch (_) {
      // Permission not available on this Android version — use inexact
      _exactAlarmsOk = false;
    }

    // 3. Request battery optimisation exemption so Doze doesn't delay alarms
    try {
      final batteryStatus = await Permission.ignoreBatteryOptimizations.status;
      if (!batteryStatus.isGranted) {
        await Permission.ignoreBatteryOptimizations.request();
      }
    } catch (_) {
      // Non-fatal — alarm will still fire, possibly slightly late on Doze
    }

    // 4. Create alarm-style notification channel (MAX importance + default sound)
    // FIX: Removed RawResourceAndroidNotificationSound — file didn't exist.
    // Omitting 'sound' makes the channel use the device default sound.
    final alarmChannel = AndroidNotificationChannel(
      _alarmChannelId,
      _alarmChannelName,
      description:      'Alarm-style reminders to administer medication',
      importance:       Importance.max,
      playSound:        true,
      enableVibration:  true,
      vibrationPattern: Int64List.fromList([0, 500, 300, 700, 300, 700]),
      enableLights:     true,
      ledColor:         const Color(0xFF7C3AED),
    );
    await _notifications
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(alarmChannel);

    // 5. Plugin init with notification tap handler
    // FIX: _onNotificationTap is now a top-level function (required by Flutter
    // for background isolate callbacks — instance methods are not allowed).
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _notifications.initialize(
      settings,
      onDidReceiveNotificationResponse:           _onNotificationTap,
      onDidReceiveBackgroundNotificationResponse:  _onNotificationTap,
    );
  }

  // ─── Add Reminder ──────────────────────────────────────────────────────────
  Future<void> addReminder({
    required String patientId,
    required String medicineName,
    required int    hour,
    required int    minute,
    String?         instructions,
    List<int>       repeatDays = const [1, 2, 3, 4, 5, 6, 7],
  }) async {
    await initialise();

    final ref = await _db
        .collection('medicineReminders')
        .doc(patientId)
        .collection('reminders')
        .add({
      'medicineName': medicineName,
      'hour':         hour,
      'minute':       minute,
      'instructions': instructions ?? '',
      'isActive':     true,
      'repeatDays':   repeatDays,
      'createdAt':    FieldValue.serverTimestamp(),
    });

    final notifId = ref.id.hashCode.abs() % 100000;

    for (final day in repeatDays) {
      await _scheduleWeeklyAlarm(
        notifId:      notifId + day,
        medicineName: medicineName,
        instructions: instructions ?? '',
        patientId:    patientId,
        hour:         hour,
        minute:       minute,
        weekday:      day,
      );
    }

    await ref.update({'notifId': notifId});
  }

  // ─── Delete Reminder ───────────────────────────────────────────────────────
  Future<void> deleteReminder({
    required String patientId,
    required String reminderId,
  }) async {
    await initialise();

    final doc = await _db
        .collection('medicineReminders')
        .doc(patientId)
        .collection('reminders')
        .doc(reminderId)
        .get();

    final data       = doc.data();
    final notifId    = data?['notifId']     as int? ?? 0;
    final repeatDays = (data?['repeatDays'] as List<dynamic>? ?? [1, 2, 3, 4, 5, 6, 7])
        .map((e) => e as int)
        .toList();

    for (final day in repeatDays) {
      await _notifications.cancel(notifId + day);
    }
    await doc.reference.delete();
  }

  // ─── Stream Reminders ──────────────────────────────────────────────────────
  Stream<QuerySnapshot> streamReminders(String patientId) {
    return _db
        .collection('medicineReminders')
        .doc(patientId)
        .collection('reminders')
        .where('isActive', isEqualTo: true)
        .snapshots();
  }

  // ─── Reschedule All (call on app restart) ─────────────────────────────────
  Future<void> rescheduleAll(String patientId) async {
    await initialise();

    final snap = await _db
        .collection('medicineReminders')
        .doc(patientId)
        .collection('reminders')
        .where('isActive', isEqualTo: true)
        .get();

    for (final doc in snap.docs) {
      final data         = doc.data();
      final notifId      = data['notifId']      as int?    ?? doc.id.hashCode.abs() % 100000;
      final medicine     = data['medicineName'] as String? ?? 'Medicine';
      final hour         = data['hour']         as int?    ?? 8;
      final minute       = data['minute']       as int?    ?? 0;
      final instructions = data['instructions'] as String? ?? '';
      final repeatDays   = (data['repeatDays']  as List<dynamic>? ?? [1, 2, 3, 4, 5, 6, 7])
          .map((e) => e as int)
          .toList();

      for (final day in repeatDays) {
        await _scheduleWeeklyAlarm(
          notifId:      notifId + day,
          medicineName: medicine,
          instructions: instructions,
          patientId:    patientId,
          hour:         hour,
          minute:       minute,
          weekday:      day,
        );
      }
    }
  }

  // ─── Schedule Weekly Alarm ─────────────────────────────────────────────────
  Future<void> _scheduleWeeklyAlarm({
    required int    notifId,
    required String medicineName,
    required String instructions,
    required String patientId,
    required int    hour,
    required int    minute,
    required int    weekday,
  }) async {
    final now = tz.TZDateTime.now(tz.local);

    // Find next occurrence of this weekday at the target time
    var scheduled = tz.TZDateTime(
      tz.local, now.year, now.month, now.day, hour, minute,
    );
    while (scheduled.weekday != weekday || scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    final body = instructions.isNotEmpty
        ? 'Time for $medicineName — $instructions'
        : 'Time to give $medicineName';

    // FIX: Removed RawResourceAndroidNotificationSound — file didn't exist.
    // Omitting 'sound' uses the device default notification sound.
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _alarmChannelId,
        _alarmChannelName,
        importance:       Importance.max,
        priority:         Priority.max,
        fullScreenIntent: true,
        playSound:        true,
        vibrationPattern: Int64List.fromList([0, 500, 300, 700, 300, 700]),
        enableLights:     true,
        ledColor:         const Color(0xFF7C3AED),
        ledOnMs:          500,
        ledOffMs:         300,
        channelShowBadge: true,
        ticker:           'Medicine Reminder',
        styleInformation: BigTextStyleInformation(body),
      ),
    );

    // Use exact scheduling if permitted, inexact as fallback
    final scheduleMode = _exactAlarmsOk
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;

    await _notifications.zonedSchedule(
      notifId,
      'Medicine Reminder',
      body,
      scheduled,
      details,
      uiLocalNotificationDateInterpretation:
      UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode: scheduleMode,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      payload: '$patientId|$medicineName',
    );
  }

  // ─── FCM alert to caregiver ────────────────────────────────────────────────
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