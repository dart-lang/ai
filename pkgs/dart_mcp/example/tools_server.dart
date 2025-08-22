// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A server that implements the tools API using the [ToolsSupport] mixin.
library;

import 'dart:async';
import 'dart:io' as io;

import 'package:dart_mcp/server.dart';
import 'package:dart_mcp/stdio.dart';

void main() {
  // Create the server and connect it to stdio.
  MCPServerWithTools(stdioChannel(input: io.stdin, output: io.stdout));
}

/// This server uses the [ToolsSupport] mixin to provide tools to the client.
base class MCPServerWithTools extends MCPServer with ToolsSupport {
  MCPServerWithTools(super.channel)
    : super.fromStreamChannel(
        implementation: Implementation(
          name: 'An example dart server with tools support',
          version: '0.1.0',
        ),
        instructions: 'Just list and call the tools :D',
      ) {
    registerTool(concatTool, _concat);
  }

  /// A tool that concatenates a list of strings.
  final concatTool = Tool(
    name: 'concat',
    description: 'concatenates many string parts into one string',
    inputSchema: Schema.object(
      properties: {
        'parts': Schema.list(
          description: 'The parts to concatenate together',
          items: Schema.string(),
        ),
        'delay': Schema.int(
          description:
              'Duration in milliseconds to delay the response, if passed '
              'progress events will be sent every 100ms',
        ),
      },
      required: ['parts'],
    ),
  );

  /// The implementation of the `concat` tool.
  FutureOr<CallToolResult> _concat(CallToolRequest request) async {
    if (request.arguments!['delay'] case final int delay?) {
      Timer? timer;
      if (request.meta?.progressToken case final progressToken?) {
        final watch = Stopwatch()..start();
        timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
          io.stderr.write('Tick ${timer.tick}');
          notifyProgress(
            ProgressNotification(
              progressToken: progressToken,
              progress: watch.elapsedMilliseconds,
              total: delay,
              message:
                  'Calculating.... ${delay - watch.elapsedMilliseconds}ms left',
            ),
          );
        });
      } else {
        io.stderr.writeln('No progress token');
      }
      await Future<void>.delayed(Duration(milliseconds: delay));
      timer?.cancel();
    } else {
      io.stderr.writeln('No delay given');
    }
    return CallToolResult(
      content: [
        TextContent(
          text: (request.arguments!['parts'] as List<dynamic>)
              .cast<String>()
              .join(''),
        ),
      ],
    );
  }
}
