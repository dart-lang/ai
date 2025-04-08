// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:dart_mcp/server.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  test('client can list and get prompts from the server', () async {
    var environment = TestEnvironment(
      TestMCPClient(),
      (c) => TestMCPServerWithPrompts(channel: c),
    );
    var initializeResult = await environment.initializeServer();

    expect(
      initializeResult.capabilities,
      ServerCapabilities(prompts: Prompts(listChanged: true)),
    );

    var serverConnection = environment.serverConnection;

    var promptsResult = await serverConnection.listPrompts(
      ListPromptsRequest(),
    );
    expect(promptsResult.prompts, [TestMCPServerWithPrompts.greeting]);

    var greetingResult = await serverConnection.getPrompt(
      GetPromptRequest(
        name: promptsResult.prompts.single.name,
        arguments: {'style': 'joyously'},
      ),
    );

    expect(
      greetingResult.messages.single,
      PromptMessage(
        role: Role.user,
        content: [TextContent(text: 'Please greet me joyously')],
      ),
    );
  });

  test('client is notified of changes to prompts from the server', () async {
    var environment = TestEnvironment(
      TestMCPClient(),
      (c) => TestMCPServerWithPrompts(channel: c),
    );
    await environment.initializeServer();

    var serverConnection = environment.serverConnection;
    expect(
      serverConnection.promptListChanged,
      emitsInOrder([
        PromptListChangedNotification(),
        PromptListChangedNotification(),
      ]),
      reason: 'We should get a notification for new and removed prompts',
    );

    var server = environment.server;
    server.addPrompt(
      Prompt(name: 'new prompt'),
      (_) => GetPromptResult(messages: []),
    );
    server.removePrompt('new prompt');
    // Give the notifications a chance to propagate.
    await pumpEventQueue();

    // We need to manually shut down so that the queue of prompt changes doesn't
    // keep the test active.
    await environment.shutdown();
  });
}

final class TestMCPServerWithPrompts extends TestMCPServer with PromptsSupport {
  TestMCPServerWithPrompts({required super.channel});

  @override
  FutureOr<InitializeResult> initialize(InitializeRequest request) {
    addPrompt(greeting, _greetingPrompt);
    return super.initialize(request);
  }

  FutureOr<GetPromptResult> _greetingPrompt(GetPromptRequest request) {
    return GetPromptResult(
      messages: [
        PromptMessage(
          role: Role.user,
          content: [
            TextContent(text: 'Please greet me ${request.arguments!['style']}'),
          ],
        ),
      ],
    );
  }

  static final greeting = Prompt(
    name: 'greet me',
    description: 'A prompt for the AI to give a greeting of a particular style',
    arguments: [
      PromptArgument(
        name: 'style',
        description: 'The style in which the greeting should be (for example, '
            '"joyously" or "angrily")',
        required: true,
      ),
    ],
  );
}
