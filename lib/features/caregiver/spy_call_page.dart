import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zego_express_engine/zego_express_engine.dart';
import 'package:neuroguard/core/services/spy_call_service.dart';
import 'package:neuroguard/core/providers/spy_call_provider.dart';

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
  bool _inCall = false;
  int _viewID = -1;
  String? _streamID;

  @override
  void initState() {
    super.initState();

    // Trigger Firebase immediately (OK)
    if (widget.videoEnabled) {
      SpyCallService.triggerVideoCall(widget.patientId);
    } else {
      SpyCallService.triggerAudioCall(widget.patientId);
    }

    // ✅ Delay provider update (THIS FIXES CRASH)
    Future.microtask(() {
      if (widget.videoEnabled) {
        ref.read(spyCallProvider.notifier).triggerAudioVideo();
      } else {
        ref.read(spyCallProvider.notifier).triggerAudioOnly();
      }
    });

    Future.microtask(_startCall);
  }

  Future<void> _startCall() async {
    ZegoExpressEngine.onRoomStreamUpdate = (
        roomID,
        updateType,
        streamList,
        extendedData,
        ) async {
      if (updateType == ZegoUpdateType.Add && streamList.isNotEmpty) {
        final streamID = streamList.first.streamID;
        _streamID = streamID;

        final viewID = DateTime.now().millisecondsSinceEpoch;
        _viewID = viewID;

        await ZegoExpressEngine.instance.startPlayingStream(
          streamID,
          canvas: ZegoCanvas(
            viewID,
            viewMode: ZegoViewMode.AspectFill,
          ),
        );

        if (mounted) setState(() {});
      }

      if (updateType == ZegoUpdateType.Delete && streamList.isNotEmpty) {
        await ZegoExpressEngine.instance
            .stopPlayingStream(streamList.first.streamID);

        _streamID = null;
        _viewID = -1;

        if (mounted) setState(() {});
      }
    };

    await SpyCallService.joinRoom(
      userId: widget.caregiverId,
      userName: 'Caregiver',
      patientId: widget.patientId,
      enableCamera: false,
    );

    if (mounted) setState(() => _inCall = true);
  }

  Widget _buildVideoView() {
    if (_viewID == -1) return const SizedBox();

    if (Platform.isAndroid) {
      return AndroidView(
        viewType: 'zego_express_engine_view',
        creationParams: {'viewID': _viewID},
        creationParamsCodec: const StandardMessageCodec(),
      );
    } else {
      return UiKitView(
        viewType: 'zego_express_engine_view',
        creationParams: {'viewID': _viewID},
        creationParamsCodec: const StandardMessageCodec(),
      );
    }
  }

  Future<void> _hangUp() async {
    ZegoExpressEngine.onRoomStreamUpdate = null;

    if (_streamID != null) {
      await ZegoExpressEngine.instance.stopPlayingStream(_streamID!);
    }

    await SpyCallService.leaveRoom(widget.patientId);
    await SpyCallService.resetTrigger(widget.patientId);
    ref.read(spyCallProvider.notifier).reset();

    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    ZegoExpressEngine.onRoomStreamUpdate = null;

    if (_streamID != null) {
      ZegoExpressEngine.instance.stopPlayingStream(_streamID!);
    }

    SpyCallService.leaveRoom(widget.patientId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (_viewID != -1)
            Positioned.fill(child: _buildVideoView())
          else
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),

          if (_inCall)
            Positioned(
              bottom: 60,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: _hangUp,
                  child: Container(
                    width: 70,
                    height: 70,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.call_end,
                      color: Colors.white,
                      size: 32,
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