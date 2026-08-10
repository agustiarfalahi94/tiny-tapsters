import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';

/// The two background tracks: one for the menus, one for the games.
enum MusicTrack { menu, game }

/// Where the music actually goes.
///
/// Exists so the service's track and volume logic can be tested without an
/// audio platform to talk to — everything below the sink is a plugin call.
abstract interface class MusicSink {
  Future<void> loop(String assetPath, double volume);
  Future<void> stop();

  /// Holds the track where it is. Unlike [stop], a later [resume] carries on
  /// rather than starting the theme again from the top.
  Future<void> pause();
  Future<void> resume();
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
  ///
  /// Every asset is normalised to the same RMS by `tool/normalize_audio.py`,
  /// so this number now means something: the music really is about 9 dB under
  /// a sound effect played at 0.9, rather than "whatever those two files
  /// happened to be mastered at".
  static const _baseVolume = 0.3;

  /// How far the music drops while a win or lose sound plays.
  static const _duckFactor = 0.35;

  MusicSink? _sink;
  MusicSink get _out => _sink ??= _AudioPlayerSink();

  MusicTrack? _current;

  /// The track actually loaded in the sink, which is not the same as the one
  /// the app wants while muted or backgrounded.
  MusicTrack? _loaded;
  bool _enabled = true;
  bool _ducked = false;
  bool _backgrounded = false;

  /// A standing reduction for screens that need the music quieter throughout,
  /// rather than the momentary [duck]. "Which Animal?" turns it down so a call
  /// is easy to make out — but does not silence it, because a game with no
  /// music at all reads as broken.
  double _attenuation = 1.0;

  /// The track that *should* be playing — tracked even while muted, so
  /// unmuting resumes wherever the child happens to be.
  MusicTrack? get currentTrack => _current;

  bool get enabled => _enabled;

  /// The standing level for the current screen, 1.0 everywhere except the
  /// screens that ask for quieter music.
  double get attenuation => _attenuation;

  double get _volume =>
      _baseVolume * _attenuation * (_ducked ? _duckFactor : 1.0);

  /// Sets the standing music level for the current screen, 0..1.
  Future<void> setAttenuation(double factor) async {
    final clamped = factor.clamp(0.0, 1.0);
    if (_attenuation == clamped) return;
    _attenuation = clamped;
    try {
      await _out.setVolume(_volume);
    } catch (e) {
      debugPrint('MusicService attenuation failed: $e');
    }
  }

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

  /// Follows the app in and out of the foreground.
  ///
  /// Locking the phone mid-game used to leave the theme playing in a pocket:
  /// the games paused their clocks on background but nothing told the music.
  Future<void> setForeground(bool foreground) async {
    if (_backgrounded != foreground) return;
    _backgrounded = !foreground;
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
      if (_backgrounded) {
        // Only the app went away, so hold the position — coming back should
        // continue the track, not restart it.
        if (_loaded != null) await _out.pause();
        return;
      }
      if (!_enabled || track == null) {
        await _out.stop();
        _loaded = null;
        return;
      }
      if (_loaded == track) {
        await _out.resume();
        await _out.setVolume(_volume);
        return;
      }
      await _out.loop(_assets[track]!, _volume);
      _loaded = track;
    } catch (e) {
      // Music is decoration. Losing it must never take a game down with it.
      debugPrint('MusicService failed: $e');
    }
  }
}

/// Pauses the music whenever the app leaves the foreground. Registered once
/// in `main()`.
class MusicLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    MusicService.instance.setForeground(state == AppLifecycleState.resumed);
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
  Future<void> pause() async => _player?.pause();

  @override
  Future<void> resume() async => _player?.resume();

  @override
  Future<void> setVolume(double volume) async => _player?.setVolume(volume);
}
