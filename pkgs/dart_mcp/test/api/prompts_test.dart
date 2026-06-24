// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:async/async.dart';
import 'package:checks/checks.dart';
import 'package:dart_mcp/server.dart';
import 'package:test/test.dart';

import '../test_utils.dart';

void main() {
  test('client can list and get prompts from the server', () async {
    final environment = TestEnvironment(
      TestMCPClient(),
      TestMCPServerWithPrompts.new,
    );
    final initializeResult = await environment.initializeServer();

    check(initializeResult.capabilities as Map<String, Object?>).deepEquals(
      ServerCapabilities(prompts: Prompts(listChanged: true))
          as Map<String, Object?>,
    );

    final serverConnection = environment.serverConnection;

    final promptsResult = await serverConnection.listPrompts();
    check(
      promptsResult.prompts as List<Object?>,
    ).deepEquals([TestMCPServerWithPrompts.greeting as Map<String, Object?>]);

    final greetingResult = await serverConnection.getPrompt(
      GetPromptRequest(
        name: promptsResult.prompts.single.name,
        arguments: {'style': 'joyously'},
      ),
    );

    check(greetingResult.messages.single as Map<String, Object?>).deepEquals(
      PromptMessage(
            role: Role.user,
            content: TextContent(text: 'Please greet me joyously'),
          )
          as Map<String, Object?>,
    );
  });

  test('client is notified of changes to prompts from the server', () async {
    final environment = TestEnvironment(
      TestMCPClient(),
      TestMCPServerWithPrompts.new,
    );
    await environment.initializeServer();

    final serverConnection = environment.serverConnection;
    final queue = StreamQueue(serverConnection.promptListChanged);

    final inOrderFuture = check(queue).inOrder([
      (s) => s.emits(
        (e) => e
            .has((x) => x as Map<String, Object?>, 'as Map')
            .deepEquals(
              PromptListChangedNotification() as Map<String, Object?>,
            ),
      ),
      (s) => s.emits(
        (e) => e
            .has((x) => x as Map<String, Object?>, 'as Map')
            .deepEquals(
              PromptListChangedNotification() as Map<String, Object?>,
            ),
      ),
      (s) => s.emits((e) => e.isNull()),
    ]);

    final server = environment.server;
    server.addPrompt(
      Prompt(name: 'new prompt'),
      (_) => GetPromptResult(messages: []),
    );
    server.removePrompt('new prompt');
    server.sendNotification(PromptListChangedNotification.methodName);
    // Give the notifications a chance to propagate.
    await pumpEventQueue();

    await inOrderFuture;
    await queue.cancel();

    // We need to manually shut down so that the queue of prompt changes doesn't
    // keep the test active.
    await environment.shutdown();
  });
}

final class TestMCPServerWithPrompts extends TestMCPServer with PromptsSupport {
  TestMCPServerWithPrompts(super.channel);

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
          content: TextContent(
            text: 'Please greet me ${request.arguments!['style']}',
          ),
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
        description:
            'The style in which the greeting should be (for example, '
            '"joyously" or "angrily")',
        required: true,
      ),
    ],
  );
}
