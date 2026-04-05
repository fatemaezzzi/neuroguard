import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:neuroguard/core/providers/spy_call_provider.dart';
import 'package:neuroguard/core/services/spy_call_service.dart';

class SpyCallListener extends ConsumerStatefulWidget {
  final String patientId;
  final Widget child;

  const SpyCallListener({
    super.key,
    required this.patientId,
    required this.child,
  });

  @override
  ConsumerState<SpyCallListener> createState() => _SpyCallListenerState();
}

class _SpyCallListenerState extends ConsumerState<SpyCallListener> {
  StreamSubscription<DocumentSnapshot>? _sub;
  bool _callActive = false;

  @override
  void initState() {
    super.initState();
    _startListening();
  }

  void _startListening() {
    _sub = FirebaseFirestore.instance
        .collection('users')       // changed from 'patients'
        .doc(widget.patientId)     // Firebase Auth UID — same on both sides
        .snapshots()
        .listen((snapshot) {
      if (!snapshot.exists) return;

      final data = snapshot.data();
      if (data == null) return;

      final commands = data['commands'] as Map<String, dynamic>?;
      if (commands == null) return;

      final shouldCall = commands['trigger_spy_call'] as bool? ?? false;
      final mode = commands['spy_call_mode'] as String? ?? 'audio';

      if (shouldCall && !_callActive) {
        _joinAsPatient(mode: mode);
      }

      if (!shouldCall && _callActive) {
        _leaveAsPatient();
      }
    });
  }

  Future<void> _joinAsPatient({required String mode}) async {
    _callActive = true;
    final isVideo = mode == 'video';

    if (isVideo) {
      ref.read(spyCallProvider.notifier).triggerAudioVideo();
    } else {
      ref.read(spyCallProvider.notifier).triggerAudioOnly();
    }

    final engine = SpyCallService.engine;
    final agoraUid = SpyCallService.uidFromFirebaseId(widget.patientId);

    await engine.enableAudio();
    await engine.enableVideo();

    if (isVideo) {
      await engine.startPreview();
    }

    await engine.joinChannel(
      token: '',
      channelId: SpyCallService.channelName(widget.patientId),
      uid: agoraUid,
      options: ChannelMediaOptions(
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
        channelProfile: ChannelProfileType.channelProfileCommunication,
        publishCameraTrack: isVideo,
        publishMicrophoneTrack: true,
        autoSubscribeAudio: false,
        autoSubscribeVideo: false,
      ),
    );

    debugPrint('SpyCall Patient: joined channel as uid=$agoraUid');
  }

  Future<void> _leaveAsPatient() async {
    final engine = SpyCallService.engine;
    await engine.stopPreview();
    await engine.leaveChannel();
    ref.read(spyCallProvider.notifier).reset();
    _callActive = false;
    debugPrint('SpyCall Patient: left channel');
  }

  @override
  void dispose() {
    _sub?.cancel();
    if (_callActive) {
      SpyCallService.engine.stopPreview();
      SpyCallService.engine.leaveChannel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}