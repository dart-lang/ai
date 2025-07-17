// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A server that makes an elicitation request to the client using the
/// [ElicitationRequestSupport] mixin.
library;

import 'dart:io' as io;

import 'package:dart_mcp/server.dart';
import 'package:dart_mcp/stdio.dart';

void main() {
  // Create the server and connect it to stdio.
  MCPServerWithElicitation(stdioChannel(input: io.stdin, output: io.stdout));
}

/// This server uses the [ElicitationRequestSupport] mixin to make elicitation
/// requests to the client.
base class MCPServerWithElicitation extends MCPServer
    with LoggingSupport, ElicitationRequestSupport {
  MCPServerWithElicitation(super.channel)
    : super.fromStreamChannel(
        implementation: Implementation(
          name: 'An example dart server which makes elicitations',
          version: '0.1.0',
        ),
        instructions: 'Handle the elicitations and ask the user for the values',
      ) {
    // You must wait for initialization to complete before you can make an
    // elicitation request.
    initialized.then((_) => _elicitName());
  }

  /// Elicits a name from the user, and logs a message based on the response.
  void _elicitName() async {
    final response = await elicit(
      ElicitRequest(
        message: 'I would like to ask you some personal information.',
        requestedSchema: Schema.object(
          properties: {
            'name': Schema.string(),
            'age': Schema.int(),
            'gender': Schema.string(enumValues: ['male', 'female', 'other']),
          },
        ),
      ),
    );
    switch (response.action) {
      case ElicitationAction.accept:
        final {'age': int age, 'name': String name, 'gender': String gender} =
            (response.content as Map<String, dynamic>);
        log(
          LoggingLevel.warning,
          'Hello $name! I see that you are $age years '
          'old and identify as $gender',
        );
      case ElicitationAction.reject:
        log(LoggingLevel.warning, 'Request for name was rejected');
      case ElicitationAction.cancel:
        log(LoggingLevel.warning, 'Request for name was cancelled');
    }

    // Ask again after a second.
    await Future<void>.delayed(const Duration(seconds: 1));
    _elicitName();
  }
}
