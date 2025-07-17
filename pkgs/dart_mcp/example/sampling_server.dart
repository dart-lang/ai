// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A server that makes sampling requests to a client.
library;

import 'dart:async';
import 'dart:io' as io;

import 'package:dart_mcp/server.dart';
import 'package:dart_mcp/stdio.dart';

void main() {
  // Create the server and connect it to stdio.
  MCPServerWithSampling(stdioChannel(input: io.stdin, output: io.stdout));
}

/// This server uses the [createMessage] function to make sampling requests
/// to the client.
base class MCPServerWithSampling extends MCPServer with LoggingSupport {
  MCPServerWithSampling(super.channel)
    : super.fromStreamChannel(
        implementation: Implementation(
          name: 'An example dart server which makes sampling requests',
          version: '0.1.0',
        ),
        instructions: 'Just respond to the requests',
      ) {
    // You can't make requests until after we are fully initialized.
    unawaited(initialized.then((_) => _makeSamplingRequest()));
  }

  /// Makes a sampling request and logs the response.
  void _makeSamplingRequest() async {
    // Actually send the request.
    final result = await createMessage(
      CreateMessageRequest(
        // All of the messages to be included in the context for the sampling
        // request.
        messages: [
          SamplingMessage(
            // The role to be assigned the message in the context.
            role: Role.user,
            // The actual content of the message in the context.
            content: Content.text(text: 'Hello'),
          ),
        ],
        // The maximum response size in tokens.
        maxTokens: 1000,
        // This controls how much additional context to include from the
        // original chat in the sampling request. Note that clients may not
        // respect this argument.
        includeContext: IncludeContext.none,
      ),
    );
    // Simply log the result, the client will print this to the console.
    log(
      LoggingLevel.warning,
      '(${result.role}): ${(result.content as TextContent).text}',
    );
  }
}
