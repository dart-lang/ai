// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A client that interacts with a server that provides prompts and completions
/// for the prompt arguments.
library;

import 'dart:async';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/stdio.dart';

void main() async {
  try {
    // Change the stdin mode so we can handle bytes one at a time, to intercept
    // the tab key for auto complete.
    stdin.echoMode = false;
    stdin.lineMode = false;

    // Create the client, which is the top level object that manages all
    // server connections.
    final client = MCPClient(
      Implementation(name: 'example dart client', version: '0.1.0'),
    );
    print('connecting to server');

    // Start the server as a separate process.
    final process = await Process.start('dart', [
      'run',
      'example/prompts_and_completions_server.dart',
    ]);
    // Connect the client to the server.
    final server = client.connectServer(
      stdioChannel(input: process.stdout, output: process.stdin),
    );
    // When the server connection is closed, kill the process.
    unawaited(server.done.then((_) => process.kill()));
    print('server started');

    // Initialize the server and let it know our capabilities.
    print('initializing server');
    final initializeResult = await server.initialize(
      InitializeRequest(
        protocolVersion: ProtocolVersion.latestSupported,
        capabilities: client.capabilities,
        clientInfo: client.implementation,
      ),
    );
    print('initialized: $initializeResult');

    // Ensure the server supports the prompts capability.
    if (initializeResult.capabilities.prompts == null) {
      await server.shutdown();
      throw StateError('Server doesn\'t support prompts!');
    }

    // Ensure the server supports the completions capability.
    if (initializeResult.capabilities.completions == null) {
      await server.shutdown();
      throw StateError('Server doesn\'t support completions!');
    }

    // Notify the server that we are initialized.
    server.notifyInitialized();
    print('sent initialized notification');

    // List all the available prompts from the server.
    print('Listing prompts from server');
    final promptsResult = await server.listPrompts(ListPromptsRequest());

    // Iterate each prompt and have the user fill in the arguments.
    for (final prompt in promptsResult.prompts) {
      print(
        'Found prompt ${prompt.name}, fill in the following arguments using '
        'tab to complete them:',
      );
      // For each argument, get a value from the user.
      final arguments = <String, Object?>{};
      for (var argument in prompt.arguments!) {
        stdout.write('${argument.name}: ');
        // The current user query.
        var current = '';
        // Read characters until we get an enter key.
        while (true) {
          final next = stdin.readByteSync();
          // User pressed tab, lets do an auto complete
          if (next == 9) {
            final completeResult = await server.requestCompletions(
              CompleteRequest(
                // The ref is the current prompt name.
                ref: PromptReference(name: prompt.name),
                argument: CompletionArgument(
                  name: argument.name,
                  value: current,
                ),
              ),
            );
            // Just auto-fill the first completion for this example
            if (completeResult.completion.values.isNotEmpty) {
              final firstResult = completeResult.completion.values.first;
              stdout.write(firstResult.substring(current.length));
              current = firstResult;
            }
            // If there are no completions, just do nothing.
          } else if (next == 10) {
            // Enter key, assign the argument and break the loop.
            arguments[argument.name] = current;
            stdout.writeln('');
            break;
          } else if (next == 127) {
            // Backspace keypress.
            if (current.isNotEmpty) {
              // Write a backspace followed by a space and then another
              // backspace to clear one character.
              stdout.write('\b \b');
              // Trim current by one.
              current = current.substring(0, current.length - 1);
            }
          } else {
            // A regular character, just add it to current and print it to the
            // console.
            final character = String.fromCharCode(next);
            current += character;
            stdout.write(character);
          }
        }
      }

      // Now fetch the full prompt with the arguments filled in.
      final promptResult = await server.getPrompt(
        GetPromptRequest(name: prompt.name, arguments: arguments),
      );
      final promptText = promptResult.messages
          .map((m) => (m.content as TextContent).text)
          .join('');

      // Finally, print the prompt to the user.
      print('Got full prompt `${prompt.name}`: "$promptText"');
    }

    // Shutdown the client, which will also shutdown the server connection.
    await client.shutdown();
  } finally {
    // Reset the terminal modes.
    stdin.echoMode = true;
    stdin.lineMode = true;
  }
}
