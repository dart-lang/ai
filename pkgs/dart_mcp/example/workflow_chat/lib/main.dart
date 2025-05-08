// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Added import

// Updated imports to point to new locations
import 'chat_screen.dart'; // ChatScreen is now in its own file

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const ChatApp());
}

class ChatApp extends StatefulWidget {
  const ChatApp({super.key});

  @override
  State<ChatApp> createState() => _ChatAppState();
}

class _ChatAppState extends State<ChatApp> {
  ThemeMode _themeMode = ThemeMode.dark; // Default theme

  @override
  void initState() {
    super.initState();
    _loadThemePreference();
  }

  Future<void> _loadThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    // Load the saved theme preference. Default to 'dark' if nothing is saved.
    final savedTheme = prefs.getString('themeMode');

    if (mounted) {
      setState(() {
        if (savedTheme == 'light') {
          _themeMode = ThemeMode.light;
        } else {
          _themeMode = ThemeMode.dark;
        }
      });
    }
  }

  Future<void> _saveThemePreference(ThemeMode themeMode) async {
    final prefs = await SharedPreferences.getInstance();
    String themeToSave;
    if (themeMode == ThemeMode.light) {
      themeToSave = 'light';
    } else {
      themeToSave = 'dark';
    }
    await prefs.setString('themeMode', themeToSave);
  }

  void _toggleTheme() {
    setState(() {
      if (_themeMode == ThemeMode.light) {
        _themeMode = ThemeMode.dark;
      } else if (_themeMode == ThemeMode.dark) {
        _themeMode = ThemeMode.light;
      }
      _saveThemePreference(_themeMode); // Save the new preference
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dash Chat',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: _themeMode,
      home: ChatScreen(onToggleTheme: _toggleTheme), // Pass the callback
    );
  }
}
