import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';

class SpyCallService {
  static const String appId = 'af07e9c632254e468d204c64b8970958';

  static RtcEngine? _engine;

  static RtcEngine get engine => _engine!;

  static Future<void> init() async {
    _engine = createAgoraRtcEngine();
    await _engine!.initialize(const RtcEngineContext(
      appId: appId,
      channelProfile: ChannelProfileType.channelProfileCommunication,
    ));
  }

  static int uidFromFirebaseId(String firebaseUid) {
    int hash = 5381;
    for (final char in firebaseUid.codeUnits) {
      hash = ((hash << 5) + hash) + char;
      hash = hash & 0x7FFFFFFF;
    }
    return hash == 0 ? 1 : hash;
  }

  static String channelName(String patientId) => 'neuroguard_$patientId';

  // ── Firestore triggers — correct path matches your DB structure ───────────
  static Future<void> triggerAudioCall(String patientId) async {
    await FirebaseFirestore.instance
        .collection('users') // changed from 'patients'
        .doc(patientId) // this is the Firebase Auth UID
        .update({
      'commands.trigger_spy_call': true,
      'commands.spy_call_mode': 'audio',
    });
  }

  static Future<void> triggerVideoCall(String patientId) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(patientId)
        .update({
      'commands.trigger_spy_call': true,
      'commands.spy_call_mode': 'video',
    });
  }

  static Future<void> resetTrigger(String patientId) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(patientId)
        .update({
      'commands.trigger_spy_call': false,
      'commands.spy_call_mode': 'none',
    });
  }
}