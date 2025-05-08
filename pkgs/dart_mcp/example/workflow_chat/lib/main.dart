// ignore_for_file: avoid_print

import 'package:flutter/material.dart';

// Updated imports to point to new locations
import 'chat_screen.dart'; // ChatScreen is now in its own file

const String _apiKey = String.fromEnvironment('GEMINI_API_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (_apiKey.isEmpty) {
    throw ArgumentError(
      'To run this app, you need to pass in your Gemini API key using '
      '--dart-define=GEMINI_API_KEY=YOUR_API_KEY',
    );
  }

  runApp(const ChatApp());
}

class ChatApp extends StatelessWidget {
  const ChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dash Chat',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const ChatScreen(), // ChatScreen is now imported
    );
  }
}
