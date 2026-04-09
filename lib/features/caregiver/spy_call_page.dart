import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:neuroguard/core/providers/spy_call_provider.dart';
import 'package:neuroguard/core/services/spy_call_service.dart';

class SpyCallPage extends ConsumerStatefulWidget {
  final String patientId;
  final String caregiverId;
  final bool videoEnabled;

  const SpyCallPage({
    super.key,
    required this.patientId,
    required this.caregiverId,
    this.videoEnabled = false,
  });

  @override
  ConsumerState<SpyCallPage> createState() => _SpyCallPageState();
}

class _SpyCallPageState extends ConsumerState<SpyCallPage> {
  bool _remoteJoined = false;
  int _remoteUid = 0;
  bool _hanging = false;

  // The patient's Agora uid — computed from their Firebase UID
  late final int _patientAgoraUid;

  @override
  void initState() {
    super.initState();
    _patientAgoraUid = SpyCallService.uidFromFirebaseId(widget.patientId);
    _setupCallbacks();
    _startCall();
  }

  void _setupCallbacks() {
    SpyCallService.engine.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (connection, elapsed) {
          debugPrint('SpyCall Caregiver: joined channel');
        },
        onUserJoined: (connection, remoteUid, elapsed) {
          debugPrint('SpyCall: remote user joined uid=$remoteUid');
          // Only react to the patient's uid specifically
          if (remoteUid == _patientAgoraUid && mounted) {
            setState(() {
              _remoteJoined = true;
              _remoteUid = remoteUid;
            });
          }
        },
        onUserOffline: (connection, remoteUid, reason) {
          debugPrint('SpyCall: remote user left uid=$remoteUid');
          if (remoteUid == _patientAgoraUid && mounted) {
            setState(() {
              _remoteJoined = false;
              _remoteUid = 0;
            });
          }
        },
        onError: (err, msg) {
          debugPrint('SpyCall ERROR: code=$err msg=$msg');
        },
      ),
    );
  }

  Future<void> _startCall() async {
    await SpyCallService.ensureInitialized();
    if (widget.videoEnabled) {
      await SpyCallService.triggerVideoCall(widget.patientId);
      ref.read(spyCallProvider.notifier).triggerAudioVideo();
    } else {
      await SpyCallService.triggerAudioCall(widget.patientId);
      ref.read(spyCallProvider.notifier).triggerAudioOnly();
    }

    final engine = SpyCallService.engine;
    final caregiverAgoraUid =
    SpyCallService.uidFromFirebaseId(widget.caregiverId);

    await engine.enableAudio();
    if (widget.videoEnabled) await engine.enableVideo();

    await engine.joinChannel(
      token: '',
      channelId: SpyCallService.channelName(widget.patientId),
      uid: caregiverAgoraUid, // real caregiver uid, not hardcoded
      options: ChannelMediaOptions(
        clientRoleType: ClientRoleType.clientRoleAudience,
        channelProfile: ChannelProfileType.channelProfileCommunication,
        publishCameraTrack: false,
        publishMicrophoneTrack: false,
        autoSubscribeAudio: true,
        autoSubscribeVideo: widget.videoEnabled,
      ),
    );

    debugPrint(
      'SpyCall Caregiver: joined as uid=$caregiverAgoraUid '
          'watching patient uid=$_patientAgoraUid',
    );
  }

  Future<void> _hangUp() async {
    if (_hanging) return;
    _hanging = true;

    SpyCallService.engine.unregisterEventHandler(RtcEngineEventHandler());
    await SpyCallService.engine.leaveChannel();
    await SpyCallService.resetTrigger(widget.patientId);
    ref.read(spyCallProvider.notifier).reset();

    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    SpyCallService.engine.unregisterEventHandler(RtcEngineEventHandler());
    SpyCallService.engine.leaveChannel();
    super.dispose();
  }

  Widget _buildRemoteVideo() {
    if (!widget.videoEnabled) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.hearing, color: Colors.white, size: 80),
            const SizedBox(height: 20),
            const Text(
              'Listening…',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _remoteJoined ? '● Patient connected' : 'Waiting for patient…',
              style: TextStyle(
                color: _remoteJoined ? Colors.greenAccent : Colors.white38,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    if (!_remoteJoined) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              'Connecting to patient…',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ],
        ),
      );
    }

    // AgoraVideoView manages surface lifecycle internally — no buffer issues
    return AgoraVideoView(
      controller: VideoViewController.remote(
        rtcEngine: SpyCallService.engine,
        canvas: VideoCanvas(uid: _remoteUid),
        connection: RtcConnection(
          channelId: SpyCallService.channelName(widget.patientId),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [

          // ── Patient feed ────────────────────────────────────────────────
          Positioned.fill(child: _buildRemoteVideo()),

          // ── Top label ───────────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        widget.videoEnabled ? Icons.videocam : Icons.hearing,
                        color: Colors.white,
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        widget.videoEnabled
                            ? 'Snap Trigger — Video'
                            : 'Spy Call — Audio',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Hang up button ──────────────────────────────────────────────
          Positioned(
            bottom: 48,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _hangUp,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.call_end,
                    color: Colors.white,
                    size: 34,
                  ),
                ),
              ),
            ),
          ),

        ],
      ),
    );
  }
}