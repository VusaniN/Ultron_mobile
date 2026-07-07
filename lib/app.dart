import 'package:flutter/material.dart';
import 'ui/screens/home_screen.dart';

class UltronApp extends StatelessWidget {
  const UltronApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ULTRON Mobile',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0D0D1A),
        primaryColor: const Color(0xFFFF2A5E),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFF2A5E),
          secondary: Color(0xFF00FF9D),
          surface: Color(0xFF1A1A2E),
        ),
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: Color(0xFFFF2A5E),
          selectionColor: Color(0xFFFF2A5E),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
