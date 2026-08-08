import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Tiny one-shot sound effects (a shared player reused for rapid taps).
class SoundEffects {
  SoundEffects._();

  static final SoundEffects instance = SoundEffects._();

  AudioPlayer? _player;

  /// The playful bubble "pop".
  Future<void> pop() async {
    try {
      _player ??= AudioPlayer();
      await _player!.stop(); // restart so rapid taps re-pop cleanly
      await _player!.setVolume(0.9);
      await _player!.play(AssetSource('sfx/pop.wav'));
    } catch (e) {
      debugPrint('SoundEffects failed: $e');
    }
  }
}
