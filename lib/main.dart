import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/home_screen.dart';
import 'services/app_language.dart';
import 'services/music_route_observer.dart';
import 'services/music_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Stability: never let an uncaught error kill the app or show the red
  // debug screen to a toddler. Log everything; render a friendly fallback.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exception}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught error: $error\n$stack');
    return true; // handled — keep the app running
  };
  ErrorWidget.builder = (details) => const _KidFriendlyError();
  // Keep the app in portrait and hide the system bars for a distraction-free
  // toddler experience.
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  // Every audioplayers player asks Android for AudioFocus.gain by default —
  // an *exclusive* request. So each bubble pop, fanfare and animal call told
  // the system to stop other audio, and the system duly stopped our own
  // music: it died under Bubble Pop's rapid taps and never came back after a
  // win. All of this app's sound is our own, mixed by us, so no player should
  // be grabbing focus from another.
  AudioPlayer.global.setAudioContext(
    AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build(),
  );
  // Locking the phone must stop the music, not leave it playing in a
  // pocket. The games already paused their clocks; nothing told the music.
  WidgetsBinding.instance.addObserver(MusicLifecycleObserver());
  // Read the stored language before the first frame, so the app never shows
  // English and then flips.
  await AppLanguageService.instance.load();
  runApp(const ToddlerGamesApp());
}

/// Fallback UI for build errors: friendly and colorful instead of the
/// default red/yellow debug screen.
class _KidFriendlyError extends StatelessWidget {
  const _KidFriendlyError();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF7FD8FF),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: const Text(
        'Oops! Something went wrong. Please go back and keep playing! 🐻',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 18, color: Colors.white),
      ),
    );
  }
}

class ToddlerGamesApp extends StatelessWidget {
  const ToddlerGamesApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Rebuilds the entire app when the language changes, which is why the
    // strings can be read from a plain global rather than looked up.
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: AppLanguageService.instance.current,
      builder: (context, _, _) => _app(),
    );
  }

  Widget _app() {
    return MaterialApp(
      title: 'Tiny Tapsters',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF7C4DFF)),
        useMaterial3: true,
      ),
      // Keeps the background music in step with whichever screen is on top.
      navigatorObservers: [MusicRouteObserver()],
      // Deliberately not `const`. A const widget is canonicalised to a single
      // instance, and Flutter skips rebuilding a subtree whose widget is
      // identical — so with `const` here the language switch changed nothing
      // on screen.
      home: HomeScreen(),
    );
  }
}
