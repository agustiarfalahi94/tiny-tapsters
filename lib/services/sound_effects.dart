import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'music_service.dart';

/// Tiny one-shot sound effects (a shared player reused for rapid taps).
class SoundEffects {
  SoundEffects._();

  static final SoundEffects instance = SoundEffects._();

  AudioPlayer? _player;
  AudioPlayer? _finishPlayer;

  /// The playful bubble "pop".
  Future<void> pop() async {
    try {
      _player ??= AudioPlayer();
      await _player!.stop(); // restart so rapid taps re-pop cleanly
      // pop.wav is a 0.12s transient and deliberately sits below the
      // normalised assets: matching a click's average level to a sustained
      // sound makes the click feel louder, not equal.
      await _player!.setVolume(0.85);
      await _player!.play(AssetSource('sfx/pop.wav'));
    } catch (e) {
      debugPrint('SoundEffects failed: $e');
    }
  }

  AudioPlayer? _animalPlayer;

  /// An animal's call, for "Which Animal?".
  ///
  /// A third player, because [pop] stops its own before every play — sharing
  /// it would let a stray tap cut a call short, and the call *is* the puzzle.
  /// The music ducks so a cow is not competing with a backing track.
  Future<void> animal(String asset) async {
    try {
      final player = _animalPlayer ??= AudioPlayer();
      await MusicService.instance.duck();
      await player.stop();
      await player.setVolume(1);
      unawaited(
        player.onPlayerComplete.first
            .then((_) => MusicService.instance.unduck())
            .catchError((_) {}),
      );
      await player.play(AssetSource(asset));
    } catch (e) {
      debugPrint('SoundEffects failed: $e');
      await MusicService.instance.unduck();
    }
  }

  /// Which fanfare a star rating earns. Three stars get the big one.
  static String winAsset(int stars) =>
      stars >= 3 ? 'sfx/win_high.m4a' : 'sfx/win_low.m4a';

  /// The little fanfare at the end of a game.
  Future<void> win(int stars) => _finish(winAsset(stars));

  /// Played when the clock runs out.
  Future<void> lose() => _finish('sfx/lose.m4a');

  /// Which finish sound is the current one. `stop()` does not complete
  /// `onPlayerComplete`, so an interrupted clip's listener would otherwise
  /// unduck the music out from under the clip that replaced it.
  int _finishGeneration = 0;

  /// Finish sounds get their own player: [pop] stops its player before every
  /// play, so sharing one would let a stray tap cut the fanfare off. The music
  /// ducks underneath for as long as the clip lasts.
  Future<void> _finish(String asset) async {
    final generation = ++_finishGeneration;
    try {
      final player = _finishPlayer ??= AudioPlayer();
      await MusicService.instance.duck();
      await player.stop();
      await player.setVolume(1);
      unawaited(
        player.onPlayerComplete.first
            .then((_) {
              if (generation == _finishGeneration) {
                MusicService.instance.unduck();
              }
            })
            .catchError((_) {}),
      );
      await player.play(AssetSource(asset));
    } catch (e) {
      debugPrint('SoundEffects failed: $e');
      // Never leave the music stuck quiet because a clip failed to play.
      if (generation == _finishGeneration) {
        await MusicService.instance.unduck();
      }
    }
  }
}
