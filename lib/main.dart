import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/home_screen.dart';
import 'services/music_player.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Keep the app in portrait and hide the system bars for a distraction-free
  // toddler experience.
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const ToddlerGamesApp());
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
