import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/home_screen.dart';

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

class ToddlerGamesApp extends StatelessWidget {
  const ToddlerGamesApp({super.key});

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
