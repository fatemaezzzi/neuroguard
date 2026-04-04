import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_database/firebase_database.dart';
//import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:zego_express_engine/zego_express_engine.dart';
import 'package:neuroguard/core/providers/spy_call_provider.dart';
import 'package:neuroguard/core/services/spy_call_service.dart';
import 'dart:async';

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
  late DatabaseReference _commandRef;
  bool _callActive = false;

  // ✅ Added to store Firebase listener
  StreamSubscription<DatabaseEvent>? _commandSub;

  @override
  void initState() {
    super.initState();
    _startListening();
  }

  // ── Exactly your existing listener logic ─────────────────────────────────
  void _startListening() {
    _commandRef = FirebaseDatabase.instance
        .ref('users/${widget.patientId}/commands');

    // ✅ Store the listener
    _commandSub = _commandRef.onValue.listen((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) return;

      final shouldCall = data['trigger_spy_call'] as bool? ?? false;
      final mode = data['spy_call_mode'] as String? ?? 'audio';

      if (shouldCall && !_callActive && mounted) {
        if (mode == 'video') {
          ref.read(spyCallProvider.notifier).triggerAudioVideo();
        } else {
          ref.read(spyCallProvider.notifier).triggerAudioOnly();
        }
        _autoJoinCall(mode: mode);
      }
    });
  }

  Future<void> _autoJoinCall({required String mode}) async {
    _callActive = true;
    final isVideo = mode == 'video';

    // Patient silently joins room — no UI shown
    await SpyCallService.joinRoom(
      userId: widget.patientId,
      userName: 'Patient',
      patientId: widget.patientId,
      enableCamera: isVideo,
    );

    // Patient stays on whatever screen they were on — no navigation
    // Call ends when caregiver hangs up and resetTrigger fires
    _commandSub = _commandRef.onValue.listen((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) return;

      final shouldCall = data['trigger_spy_call'] as bool? ?? false;
      if (!shouldCall && _callActive) {
        _endCall();
      }
    });
  }

  Future<void> _endCall() async {
    await SpyCallService.leaveRoom(widget.patientId);
    ref.read(spyCallProvider.notifier).reset();
    _callActive = false;
  }

  @override
  void dispose() {
    // ✅ Properly cancel Firebase listener
    _commandSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}