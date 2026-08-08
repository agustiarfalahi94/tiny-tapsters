import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Plays the gentle background lullaby loop on the home and game screens.
///
/// The companion screen suppresses it while open; the app root pauses it
/// whenever the app goes to the background. All calls are failure-safe so a
/// missing audio backend can never crash the app (or the widget tests).
class MusicPlayer {
  MusicPlayer._();

  static final MusicPlayer instance = MusicPlayer._();

  AudioPlayer? _player;
  bool _playing = false;
  bool _suppressed = false;

  /// Starts the loop (no-op if already playing or suppressed).
  Future<void> start() async {
    if (_playing || _suppressed) return;
    _playing = true;
    try {
      _player ??= AudioPlayer();
      await _player!.setReleaseMode(ReleaseMode.loop);
      await _player!.setVolume(0.35);
      await _player!.play(AssetSource('music/lullaby.wav'));
    } catch (e) {
      debugPrint('MusicPlayer failed: $e');
      _playing = false;
    }
  }

  /// Stops the loop.
  Future<void> stop() async {
    _playing = false;
    try {
      await _player?.stop();
    } catch (_) {}
  }

  /// Stops while the companion (Pollie) is on screen; [unsuppress] resumes.
  void suppress() {
    _suppressed = true;
    stop();
  }

  void unsuppress() {
    _suppressed = false;
    start();
  }
}
