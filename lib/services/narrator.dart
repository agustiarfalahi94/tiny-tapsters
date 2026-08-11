import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'app_language.dart';
import 'music_service.dart';

/// Says a game's name out loud when it opens.
///
/// A four-year-old cannot read "Cocokkan Kartu", so the title at the top of a
/// game tells them nothing. Hearing it does.
///
/// Spoken by the device rather than played from a recording: `flutter_tts` is
/// already here for Pollie and speaks both languages, so this follows the
/// language switch for free and costs no assets. Sixteen recorded clips would
/// need re-recording every time a game is renamed.
class Narrator {
  Narrator._();

  static final Narrator instance = Narrator._();

  final _tts = FlutterTts();
  bool _ready = false;

  /// Says [text], unless the child has the sound off.
  ///
  /// Follows the mute button: a parent who silenced the app in a waiting room
  /// meant all of it, not just the music.
  Future<void> announce(String text) async {
    if (!MusicService.instance.enabled) return;
    try {
      if (!_ready) {
        // Queue mode 0 replaces whatever is speaking — a child who taps
        // through three games quickly should hear the last one, not all three.
        await _tts.setQueueMode(0);
        _ready = true;
      }
      await _tts.setLanguage(
        AppLanguageService.instance.current.value.localeId,
      );
      await _tts.setPitch(1.1);
      await _tts.setSpeechRate(0.45);
      // Duck the music so the name is clear over it, and restore when done.
      await MusicService.instance.duck();
      _tts.setCompletionHandler(MusicService.instance.unduck);
      _tts.setCancelHandler(MusicService.instance.unduck);
      await _tts.speak(text);
    } catch (e) {
      // Never let a missing voice stop a game from opening.
      debugPrint('Narrator failed: $e');
      await MusicService.instance.unduck();
    }
  }

  /// Stops anything being said, for when a game is left quickly.
  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
    await MusicService.instance.unduck();
  }
}
