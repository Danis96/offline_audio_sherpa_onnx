import 'package:flutter/material.dart';

import 'features/live_translate/live_translate_screen.dart';

class OfflineVoiceApp extends StatelessWidget {
  const OfflineVoiceApp({super.key});

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF07111A);
    const surface = Color(0xFF0E1A24);
    const accent = Color(0xFF34D399);
    const secondary = Color(0xFF38BDF8);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Offline Voice Translate',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.dark,
          surface: surface,
          secondary: secondary,
        ),
        textTheme: ThemeData.dark().textTheme.apply(
          bodyColor: const Color(0xFFE2E8F0),
          displayColor: const Color(0xFFF8FAFC),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        cardTheme: const CardThemeData(
          color: surface,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(28)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF12212D),
          labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(color: Color(0xFF1E293B)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(color: Color(0xFF1E293B)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(color: accent, width: 1.4),
          ),
        ),
      ),
      home: const LiveTranslateScreen(),
    );
  }
}
