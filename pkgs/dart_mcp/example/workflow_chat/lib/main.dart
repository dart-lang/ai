// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chat_screen.dart';
import 'directory_input_screen.dart'; // Import the new screen

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
  ThemeMode _themeMode = ThemeMode.dark;
  String? _projectPath; // Variable to hold the project path

  @override
  void initState() {
    super.initState();
    _loadThemePreference();
    _loadLastProjectDirectory();
  }

  Future<void> _loadLastProjectDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    final String? lastProjectDir = prefs.getString('last_project_dir');
    if (lastProjectDir != null && mounted) {
      setState(() {
        _projectPath = lastProjectDir;
      });
    }
  }

  Future<void> _loadThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTheme = prefs.getString('themeMode');
    if (mounted) {
      setState(() {
        if (savedTheme == 'light') {
          _themeMode = ThemeMode.light;
        } else {
          _themeMode = ThemeMode.dark; // Default to dark
        }
      });
    }
  }

  Future<void> _saveThemePreference(ThemeMode themeMode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'themeMode',
      themeMode == ThemeMode.light ? 'light' : 'dark',
    );
  }

  void _toggleTheme() {
    setState(() {
      _themeMode =
          _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
      _saveThemePreference(_themeMode);
    });
  }

  // Callback for when the directory is submitted
  void _onDirectorySubmitted(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_project_dir', path);
    if (mounted) {
      setState(() {
        _projectPath = path;
      });
    }
  }

  // New method to request a directory change
  void _requestNewDirectory() {
    if (mounted) {
      setState(() {
        _projectPath = null;
      });
    }
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
      home:
          _projectPath == null
              ? DirectoryInputScreen(
                onDirectorySubmitted: _onDirectorySubmitted,
              )
              : ChatScreen(
                projectPath: _projectPath!,
                onToggleTheme: _toggleTheme,
                onRequestNewDirectory:
                    _requestNewDirectory, // Pass the new callback
              ),
    );
  }
}
