// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:flutter/material.dart';

class DirectoryInputScreen extends StatefulWidget {
  final Function(String) onDirectorySubmitted;

  const DirectoryInputScreen({super.key, required this.onDirectorySubmitted});

  @override
  State<DirectoryInputScreen> createState() => _DirectoryInputScreenState();
}

class _DirectoryInputScreenState extends State<DirectoryInputScreen> {
  final TextEditingController _textController = TextEditingController();

  void _submitDirectory() {
    if (_textController.text.isNotEmpty) {
      widget.onDirectorySubmitted(_textController.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Select Project Directory')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            TextField(
              controller: _textController,
              decoration: const InputDecoration(
                labelText: 'Project Directory Path',
                hintText: 'file:///path/to/your/project',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _submitDirectory,
              child: const Text('Load Project'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }
}
