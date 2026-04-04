import 'package:firebase_database/firebase_database.dart';
import 'package:zego_express_engine/zego_express_engine.dart';

class SpyCallService {
  static const int appID = 1206500765;
  static const String appSign = '1ee0960ffb2f98300a7562bb14ae465cfa1519c24d7d987ea2db41e09716de57';

  // ── Init Zego engine once at app start ───────────────────────────────────
  static Future<void> init() async {
    await ZegoExpressEngine.createEngineWithProfile(
      ZegoEngineProfile(
        appID,
        ZegoScenario.Communication,
        appSign: appSign,
      ),
    );
  }

  // ── These stay exactly the same as your current code ────────────────────
  static Future<void> triggerAudioCall(String patientId) async {
    await FirebaseDatabase.instance
        .ref('users/$patientId/commands')
        .update({
      'trigger_spy_call': true,
      'spy_call_mode': 'audio',
    });
  }

  static Future<void> triggerVideoCall(String patientId) async {
    await FirebaseDatabase.instance
        .ref('users/$patientId/commands')
        .update({
      'trigger_spy_call': true,
      'spy_call_mode': 'video',
    });
  }

  static Future<void> resetTrigger(String patientId) async {
    await FirebaseDatabase.instance
        .ref('users/$patientId/commands')
        .update({
      'trigger_spy_call': false,
      'spy_call_mode': 'none',
    });
  }

  // ── Join room (called by both caregiver and patient) ─────────────────────
  static Future<void> joinRoom({
    required String userId,
    required String userName,
    required String patientId,
    required bool enableCamera,
  }) async {
    await ZegoExpressEngine.instance.loginRoom(
      'spycall_$patientId',
      ZegoUser(userId, userName),
    );
    await ZegoExpressEngine.instance.startPublishingStream(userId);
    await ZegoExpressEngine.instance.muteMicrophone(false);
    await ZegoExpressEngine.instance.enableCamera(enableCamera);
  }

  // ── Leave room ───────────────────────────────────────────────────────────
  static Future<void> leaveRoom(String patientId) async {
    await ZegoExpressEngine.instance.stopPublishingStream();
    await ZegoExpressEngine.instance.logoutRoom('spycall_$patientId');
  }
}