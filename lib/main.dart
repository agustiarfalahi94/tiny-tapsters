import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/home_screen.dart';
import 'services/music_player.dart';

void main() {
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

class ToddlerGamesApp extends StatefulWidget {
  const ToddlerGamesApp({super.key});

  @override
  State<ToddlerGamesApp> createState() => _ToddlerGamesAppState();
}

class _ToddlerGamesAppState extends State<ToddlerGamesApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Gentle background lullaby across the home + game screens.
    MusicPlayer.instance.start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    MusicPlayer.instance.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // No music while the app is in the background.
    if (state == AppLifecycleState.resumed) {
      MusicPlayer.instance.start();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      MusicPlayer.instance.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Our Toddlers' Journey",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF7C4DFF)),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
