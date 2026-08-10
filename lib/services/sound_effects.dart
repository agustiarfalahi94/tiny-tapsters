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

  /// The playful bubble "pop" — also the "yes, that's right" everywhere else.
  ///
  /// pop.wav is a 0.12s transient and deliberately sits below the normalised
  /// assets: matching a click's average level to a sustained sound makes the
  /// click feel louder, not equal.
  Future<void> pop() => _tap('sfx/pop.wav', 0.85);

  /// The "tetot" — two descending tones on a wrong answer.
  ///
  /// Quieter than the pop on purpose. A four-year-old hears this more often
  /// than they hear the pop, and it should correct rather than scold.
  Future<void> wrong() => _tap('sfx/wrong.wav', 0.55);

  /// Tap feedback shares one player: a tap is either right or wrong, never
  /// both, and stopping first is what lets rapid taps re-trigger cleanly.
  Future<void> _tap(String asset, double volume) async {
    try {
      final player = _player ??= AudioPlayer();
      await player.stop();
      await player.setVolume(volume);
      await player.play(AssetSource(asset));
    } catch (e) {
      debugPrint('SoundEffects failed: $e');
    }
  }

  AudioPlayer? _animalPlayer;

  /// An animal's call, for "Which Animal?".
  ///
  /// A third player, because [pop] stops its own before every play — sharing
  /// it would let a stray tap cut a call short, and the call *is* the puzzle.
  Future<void> animal(String asset) =>
      _duckedPlay(_animalPlayer ??= AudioPlayer(), asset, 1);

  /// Which fanfare a star rating earns. Three stars get the big one.
  static String winAsset(int stars) =>
      stars >= 3 ? 'sfx/win_high.m4a' : 'sfx/win_low.m4a';

  /// The little fanfare at the end of a game.
  Future<void> win(int stars) => _finish(winAsset(stars));

  /// Played when the clock runs out.
  Future<void> lose() => _finish('sfx/lose.m4a');

  /// Which ducked clip is the current one.
  ///
  /// `stop()` does not complete `onPlayerComplete`, so an interrupted clip's
  /// listener would otherwise unduck the music out from under the clip that
  /// replaced it.
  int _duckGeneration = 0;

  /// Finish sounds get their own player: [pop] stops its player before every
  /// play, so sharing one would let a stray tap cut the fanfare off.
  Future<void> _finish(String asset) =>
      _duckedPlay(_finishPlayer ??= AudioPlayer(), asset, 1);

  /// Plays [asset] with the music turned down under it, and restores the
  /// music afterwards.
  ///
  /// The restore has a timer behind it as well as the completion event. If
  /// that event is ever missed — a failed decode, an interrupted clip — the
  /// music would otherwise stay quiet for the rest of the session, which is
  /// indistinguishable from the music being broken.
  Future<void> _duckedPlay(
    AudioPlayer player,
    String asset,
    double volume,
  ) async {
    final generation = ++_duckGeneration;
    void restore() {
      if (generation == _duckGeneration) MusicService.instance.unduck();
    }

    try {
      await MusicService.instance.duck();
      await player.stop();
      await player.setVolume(volume);
      unawaited(
        player.onPlayerComplete.first.then((_) => restore()).catchError((_) {}),
      );
      Timer(_duckSafety, restore);
      await player.play(AssetSource(asset));
    } catch (e) {
      debugPrint('SoundEffects failed: $e');
      restore();
    }
  }

  /// Longer than any clip the app plays (the fanfares are ~3s).
  static const _duckSafety = Duration(seconds: 6);
}
