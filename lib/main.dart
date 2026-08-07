import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Keep the app in portrait and hide the system bars for a distraction-free
  // toddler experience.
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const ToddlerGamesApp());
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
