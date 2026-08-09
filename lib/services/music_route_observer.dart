import 'package:flutter/material.dart';

import 'music_service.dart';

/// Route settings that tell [MusicRouteObserver] which track a screen wants.
/// Pass null for silence (Pollie's screen).
RouteSettings musicRoute(MusicTrack? track) =>
    RouteSettings(name: '$_prefix${track?.name ?? _silence}');

const _prefix = 'music:';
const _silence = 'none';

/// The track a route asks for, or [fallback] when it never said.
///
/// [MaterialApp.home] builds a route named '/' that we do not construct, and
/// that route is the menu.
MusicTrack? trackForRoute(Route<dynamic>? route, {MusicTrack? fallback}) {
  final name = route?.settings.name;
  if (name == null || !name.startsWith(_prefix)) return fallback;
  final value = name.substring(_prefix.length);
  if (value == _silence) return null;
  for (final track in MusicTrack.values) {
    if (track.name == value) return track;
  }
  return fallback;
}

/// Keeps the background music in step with whichever screen is on top.
///
/// A [NavigatorObserver] rather than per-screen `initState` calls, because
/// popping a game route does not re-run `HomeScreen.initState` — per-screen
/// calls would leave the game song playing over the menu.
class MusicRouteObserver extends NavigatorObserver {
  MusicRouteObserver([MusicService? music])
    : _music = music ?? MusicService.instance;

  final MusicService _music;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _sync(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _sync(previousRoute);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _sync(newRoute);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _sync(previousRoute);

  void _sync(Route<dynamic>? route) {
    if (route == null) return;
    // An unnamed route is the app's own '/' home, which is a menu.
    _music.play(trackForRoute(route, fallback: MusicTrack.menu));
  }
}
