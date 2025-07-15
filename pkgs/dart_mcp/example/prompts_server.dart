// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io' as io;

import 'package:dart_mcp/server.dart';
import 'package:dart_mcp/stdio.dart';

void main() {
  MCPServerWithPrompts(stdioChannel(input: io.stdin, output: io.stdout));
}

/// Our actual MCP server.
base class MCPServerWithPrompts extends MCPServer with PromptsSupport {
  MCPServerWithPrompts(super.channel)
    : super.fromStreamChannel(
        implementation: Implementation(
          name: 'An example dart server with prompts support',
          version: '0.1.0',
        ),
        instructions: 'Just list the prompts :D',
      );

  @override
  FutureOr<InitializeResult> initialize(InitializeRequest request) {
    addPrompt(runTestsPrompt, (request) {
      final tags = (request.arguments?['tags'] as String?)
          ?.split(' ')
          .join(',');
      final platforms = (request.arguments?['platforms'] as String?)
          ?.split(' ')
          .join(',');
      return GetPromptResult(
        messages: [
          PromptMessage(
            role: Role.user,
            content: Content.text(
              text:
                  'Execute the shell command `dart test --failures-only'
                  '${tags != null ? ' -t $tags' : ''}'
                  '${platforms != null ? ' -p $platforms' : ''}'
                  '`',
            ),
          ),
        ],
      );
    });
    return super.initialize(request);
  }

  final runTestsPrompt = Prompt(
    name: 'run_tests',
    arguments: [
      PromptArgument(
        name: 'tags',
        description: 'The test tags to include, space or comma separated',
      ),
      PromptArgument(
        name: 'platforms',
        description: 'The platforms to run on, space or comma separated',
      ),
    ],
  );
}
