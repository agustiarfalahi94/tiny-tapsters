import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_tapsters/main.dart';
import 'package:tiny_tapsters/services/music_route_observer.dart';
import 'package:tiny_tapsters/services/music_service.dart';
import 'package:tiny_tapsters/services/sound_effects.dart';

/// Records what the service asked of the audio platform, which tests have
/// none of.
class FakeMusicSink implements MusicSink {
  final calls = <String>[];
  double? volume;

  @override
  Future<void> loop(String assetPath, double volume) async {
    this.volume = volume;
    calls.add('loop $assetPath');
  }

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<void> setVolume(double volume) async {
    this.volume = volume;
    calls.add('volume');
  }
}

Route<void> routeFor(MusicTrack? track) => MaterialPageRoute<void>(
  builder: (_) => const SizedBox(),
  settings: musicRoute(track),
);

void main() {
  group('MusicService', () {
    test(
      'switching to the track already playing does not restart it',
      () async {
        final sink = FakeMusicSink();
        final music = MusicService.withSink(sink);

        await music.play(MusicTrack.menu);
        await music.play(MusicTrack.menu);

        expect(sink.calls, ['loop music/main_theme.m4a']);
      },
    );

    test('each track maps to its own asset, and null is silence', () async {
      final sink = FakeMusicSink();
      final music = MusicService.withSink(sink);

      await music.play(MusicTrack.menu);
      await music.play(MusicTrack.game);
      await music.play(null);

      expect(sink.calls, [
        'loop music/main_theme.m4a',
        'loop music/game_song.m4a',
        'stop',
      ]);
    });

    test(
      'muting stops the music and unmuting resumes the same track',
      () async {
        final sink = FakeMusicSink();
        final music = MusicService.withSink(sink);

        await music.play(MusicTrack.game);
        await music.setEnabled(false);
        expect(sink.calls.last, 'stop');
        // The track is remembered while muted, so unmuting knows where we are.
        expect(music.currentTrack, MusicTrack.game);

        await music.setEnabled(true);
        expect(sink.calls.last, 'loop music/game_song.m4a');
      },
    );

    test(
      'navigating while muted stays silent but tracks where we are',
      () async {
        final sink = FakeMusicSink();
        final music = MusicService.withSink(sink);

        await music.setEnabled(false);
        await music.play(MusicTrack.game);

        expect(sink.calls.where((c) => c.startsWith('loop')), isEmpty);
        expect(music.currentTrack, MusicTrack.game);
      },
    );

    test('ducking lowers the volume and unducking restores it', () async {
      final sink = FakeMusicSink();
      final music = MusicService.withSink(sink);

      await music.play(MusicTrack.menu);
      final playing = sink.volume!;

      await music.duck();
      expect(sink.volume, lessThan(playing));

      await music.unduck();
      expect(sink.volume, playing);
    });

    test('ducking twice does not stack', () async {
      final sink = FakeMusicSink();
      final music = MusicService.withSink(sink);

      await music.play(MusicTrack.menu);
      await music.duck();
      final ducked = sink.volume;
      await music.duck();

      expect(sink.volume, ducked);
    });
  });

  group('music routes', () {
    test('a route carries the track it asked for', () {
      expect(trackForRoute(routeFor(MusicTrack.menu)), MusicTrack.menu);
      expect(trackForRoute(routeFor(MusicTrack.game)), MusicTrack.game);
      // Pollie's screen asks for silence, which must not be confused with
      // "this route never said" — the fallback would start the music over her.
      expect(trackForRoute(routeFor(null), fallback: MusicTrack.menu), isNull);
    });

    test('an untagged route falls back — MaterialApp.home is the menu', () {
      final home = MaterialPageRoute<void>(
        builder: (_) => const SizedBox(),
        settings: const RouteSettings(name: '/'),
      );
      expect(trackForRoute(home, fallback: MusicTrack.menu), MusicTrack.menu);
      expect(trackForRoute(null, fallback: MusicTrack.menu), MusicTrack.menu);
    });

    test('popping a game restores the track of the screen underneath', () {
      final sink = FakeMusicSink();
      final music = MusicService.withSink(sink);
      final observer = MusicRouteObserver(music);

      final levels = routeFor(MusicTrack.menu);
      final game = routeFor(MusicTrack.game);

      observer.didPush(levels, null);
      observer.didPush(game, levels);
      expect(music.currentTrack, MusicTrack.game);

      // The bug an observer exists to prevent: HomeScreen.initState does not
      // re-run on pop, so a per-screen call would leave the game song playing.
      observer.didPop(game, levels);
      expect(music.currentTrack, MusicTrack.menu);
    });
  });

  group('finish sounds', () {
    test('three stars earn a different fanfare from one or two', () {
      expect(SoundEffects.winAsset(3), isNot(SoundEffects.winAsset(2)));
      expect(SoundEffects.winAsset(2), SoundEffects.winAsset(1));
    });
  });

  testWidgets('the music button toggles between speaker and muted', (
    tester,
  ) async {
    final wasEnabled = MusicService.instance.enabled;
    // Deliberately not returning the future: this is the real singleton, so
    // it talks to an audio plugin that is not registered in tests and never
    // answers. A tear-down that awaited it would hang the whole run.
    addTearDown(() {
      MusicService.instance.setEnabled(wasEnabled);
    });

    await tester.pumpWidget(const ToddlerGamesApp());
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('🔊'), findsOneWidget);
    await tester.tap(find.text('🔊'));
    await tester.pump();

    expect(find.text('🔇'), findsOneWidget);
    expect(MusicService.instance.enabled, isFalse);
  });

  testWidgets('the music button does not push the title off centre', (
    tester,
  ) async {
    await tester.pumpWidget(const ToddlerGamesApp());
    await tester.pump(const Duration(milliseconds: 100));
    // 800x600 test viewport. The button is floated over the column precisely
    // so this stays true.
    expect(tester.getCenter(find.text('Tiny Tapsters')).dx, closeTo(400, 5));
  });
}
