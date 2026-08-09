import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// The two background tracks: one for the menus, one for the games.
enum MusicTrack { menu, game }

/// Where the music actually goes.
///
/// Exists so the service's track and volume logic can be tested without an
/// audio platform to talk to — everything below the sink is a plugin call.
abstract interface class MusicSink {
  Future<void> loop(String assetPath, double volume);
  Future<void> stop();
  Future<void> setVolume(double volume);
}

/// Looping background music.
///
/// Deliberately separate from [SoundEffects]: that class calls `stop()` before
/// every play so rapid taps re-pop cleanly, and sharing a player would make
/// every pop kill the music.
class MusicService {
  MusicService._();

  @visibleForTesting
  MusicService.withSink(MusicSink sink) : _sink = sink;

  static final MusicService instance = MusicService._();

  static const _assets = {
    MusicTrack.menu: 'music/main_theme.m4a',
    MusicTrack.game: 'music/game_song.m4a',
  };

  /// Music sits under the game, never over it — the pop has to cut through.
  static const _baseVolume = 0.45;

  /// How far the music drops while a win or lose sound plays.
  static const _duckFactor = 0.25;

  MusicSink? _sink;
  MusicSink get _out => _sink ??= _AudioPlayerSink();

  MusicTrack? _current;
  bool _enabled = true;
  bool _ducked = false;

  /// The track that *should* be playing — tracked even while muted, so
  /// unmuting resumes wherever the child happens to be.
  MusicTrack? get currentTrack => _current;

  bool get enabled => _enabled;

  double get _volume => _ducked ? _baseVolume * _duckFactor : _baseVolume;

  /// Switches to [track], or to silence when null.
  ///
  /// A no-op when [track] is already playing: returning to the menu from a
  /// game must not restart the theme from the top.
  Future<void> play(MusicTrack? track) async {
    if (track == _current) return;
    _current = track;
    await _apply();
  }

  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;
    await _apply();
  }

  /// Drops the volume so a finish sound is clearly audible over the music.
  Future<void> duck() => _setDucked(true);

  Future<void> unduck() => _setDucked(false);

  Future<void> _setDucked(bool value) async {
    if (_ducked == value) return;
    _ducked = value;
    try {
      await _out.setVolume(_volume);
    } catch (e) {
      debugPrint('MusicService duck failed: $e');
    }
  }

  Future<void> _apply() async {
    try {
      final track = _current;
      if (!_enabled || track == null) {
        await _out.stop();
        return;
      }
      await _out.loop(_assets[track]!, _volume);
    } catch (e) {
      // Music is decoration. Losing it must never take a game down with it.
      debugPrint('MusicService failed: $e');
    }
  }
}

class _AudioPlayerSink implements MusicSink {
  AudioPlayer? _player;

  @override
  Future<void> loop(String assetPath, double volume) async {
    final player = _player ??= AudioPlayer();
    await player.setReleaseMode(ReleaseMode.loop);
    await player.stop();
    await player.setVolume(volume);
    await player.play(AssetSource(assetPath));
  }

  @override
  Future<void> stop() async => _player?.stop();

  @override
  Future<void> setVolume(double volume) async => _player?.setVolume(volume);
}
