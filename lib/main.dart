import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

void main() {
  runApp(const StreamboxApp());
}

class StreamboxApp extends StatelessWidget {
  const StreamboxApp({super.key});

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF19251F);
    const canvas = Color(0xFFF5F5F0);
    return MaterialApp(
      title: 'Streambox',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: canvas,
        colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFFB9F36B),
                brightness: Brightness.light)
            .copyWith(surface: canvas, onSurface: ink),
        fontFamily: 'Arial',
      ),
      home: const HomeScreen(),
    );
  }
}
