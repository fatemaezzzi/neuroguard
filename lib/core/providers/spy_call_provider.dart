import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_database/firebase_database.dart';

enum SpyCallMode { idle, audioOnly, audioVideo }

class SpyCallState {
  final SpyCallMode mode;
  final bool active;

  const SpyCallState({
    this.mode = SpyCallMode.idle,
    this.active = false,
  });

  SpyCallState copyWith({SpyCallMode? mode, bool? active}) {
    return SpyCallState(
      mode: mode ?? this.mode,
      active: active ?? this.active,
    );
  }
}

class SpyCallNotifier extends StateNotifier<SpyCallState> {
  SpyCallNotifier() : super(const SpyCallState());

  void triggerAudioOnly() {
    state = const SpyCallState(mode: SpyCallMode.audioOnly, active: true);
  }

  void triggerAudioVideo() {
    state = const SpyCallState(mode: SpyCallMode.audioVideo, active: true);
  }

  void reset() {
    state = const SpyCallState(mode: SpyCallMode.idle, active: false);
  }
}

final spyCallProvider =
    StateNotifierProvider<SpyCallNotifier, SpyCallState>((ref) {
  return SpyCallNotifier();
});