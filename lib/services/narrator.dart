import 'package:flutter/foundation.dart';

import 'app_language.dart';
import 'music_service.dart';
import 'tts_service.dart';

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

  TtsSession? _session;

  /// Says [text], unless the child has the sound off.
  ///
  /// Follows the mute button: a parent who silenced the app in a waiting room
  /// meant all of it, not just the music.
  Future<void> announce(String text) async {
    if (!MusicService.instance.enabled) return;
    try {
      // Queue mode 0 replaces whatever is speaking — a child who taps through
      // three games quickly should hear the last one, not all three. Applied
      // on every acquisition because Pollie sets mode 1 on the same engine.
      final session = await TtsService.instance.acquire(this, queueMode: 0);
      _session = session;
      session.onComplete = MusicService.instance.unduck;
      await session.setLanguage(
        AppLanguageService.instance.current.value.localeId,
      );
      await session.setPitch(1.1);
      await session.setSpeechRate(0.45);
      // Duck the music so the name is clear over it, and restore when done.
      await MusicService.instance.duck();
      await session.speak(text);
    } catch (e) {
      // Never let a missing voice stop a game from opening.
      debugPrint('Narrator failed: $e');
      await MusicService.instance.unduck();
    }
  }

  /// Stops anything being said, for when a game is left quickly.
  ///
  /// Called when Pollie's screen opens: a game-name announcement still in
  /// flight would otherwise talk over her greeting, and — because they share
  /// one engine — its completion would land on the wrong owner.
  Future<void> stop() async {
    await _session?.stop();
    _session?.release();
    _session = null;
    await MusicService.instance.unduck();
  }
}
