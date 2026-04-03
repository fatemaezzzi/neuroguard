import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import 'package:neuroguard/core/services/spy_call_service.dart';

class SpyCallPage extends StatefulWidget {
  final String patientId;
  final String caregiverId;

  const SpyCallPage({
    super.key,
    required this.patientId,
    required this.caregiverId,
  });

  @override
  State<SpyCallPage> createState() => _SpyCallPageState();
}

class _SpyCallPageState extends State<SpyCallPage> {
  @override
  void initState() {
    super.initState();
    // Write trigger so patient app auto-answers
    FirebaseDatabase.instance
        .ref('users/${widget.patientId}/commands/trigger_spy_call')
        .set(true);
  }

  Future<void> _onHangUp() async {
    // Reset Firebase trigger — Zego will close the screen itself
    await FirebaseDatabase.instance
        .ref('users/${widget.patientId}/commands/trigger_spy_call')
        .set(false);
  }

  @override
  Widget build(BuildContext context) {
    return ZegoUIKitPrebuiltCall(
      appID: SpyCallService.appID,
      appSign: SpyCallService.appSign,
      userID: widget.caregiverId,
      userName: 'Caregiver',
      callID: widget.patientId,
      config: ZegoUIKitPrebuiltCallConfig.oneOnOneVideoCall()
        ..turnOnCameraWhenJoining = false
        ..turnOnMicrophoneWhenJoining = true,
      events: ZegoUIKitPrebuiltCallEvents(
        onHangUpConfirmation: (
            ZegoCallHangUpConfirmationEvent event,
            Future<bool> Function() defaultAction,
            ) async {
          await _onHangUp();
          return true; // true = allow hang up to proceed
        },
      ),
    );
  }
}