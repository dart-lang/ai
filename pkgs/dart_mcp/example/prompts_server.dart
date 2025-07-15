// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A server that implements the prompts API using the [PromptsSupport] mixin.
library;

import 'dart:io' as io;

import 'package:dart_mcp/server.dart';
import 'package:dart_mcp/stdio.dart';

void main() {
  // Create the server and connect it to stdio.
  MCPServerWithPrompts(stdioChannel(input: io.stdin, output: io.stdout));
}

/// Our actual MCP server.
///
/// This server uses the [PromptsSupport] mixin to provide prompts to the
/// client.
base class MCPServerWithPrompts extends MCPServer with PromptsSupport {
  MCPServerWithPrompts(super.channel)
    : super.fromStreamChannel(
        implementation: Implementation(
          name: 'An example dart server with prompts support',
          version: '0.1.0',
        ),
        instructions: 'Just list the prompts :D',
      ) {
    // Actually add the prompt.
    addPrompt(runTestsPrompt, _runTestsPrompt);
  }

  /// The prompt implementation, takes in a [request] and builds the prompt
  /// by substituting in arguments.
  GetPromptResult _runTestsPrompt(GetPromptRequest request) {
    // The actual arguments should be comma separated, but we allow for space
    // separated and then convert it here.
    final tags = (request.arguments?['tags'] as String?)?.split(' ').join(',');
    final platforms = (request.arguments?['platforms'] as String?)
        ?.split(' ')
        .join(',');
    return GetPromptResult(
      messages: [
        // This is a prompt that should execute as if it came from the user,
        // instructing the LLM to run a specific CLI command based on the
        // arguments given.
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
  }

  /// A prompt that can be used to run tests.
  ///
  /// This prompt has two arguments, `tags` and `platforms`.
  final runTestsPrompt = Prompt(
    name: 'run_tests',
    description: 'Run your dart tests',
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
