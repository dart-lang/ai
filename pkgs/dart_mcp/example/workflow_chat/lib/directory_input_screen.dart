// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DirectoryInputScreen extends StatefulWidget {
  final Function(String) onDirectorySubmitted;

  const DirectoryInputScreen({super.key, required this.onDirectorySubmitted});

  @override
  State<DirectoryInputScreen> createState() => _DirectoryInputScreenState();
}

class _DirectoryInputScreenState extends State<DirectoryInputScreen> {
  Future<void> _pickDirectory() async {
    String? path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Please select your project directory',
    );

    if (path != null) {
      path = Uri.file(path).toString();
      // Path is not null means a directory was selected.
      widget.onDirectorySubmitted(path);
      // Save the selected path
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_project_dir', path);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Select Project Directory')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              ElevatedButton(
                onPressed: _pickDirectory,
                child: const Text('Choose Project Directory'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
