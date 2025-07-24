// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dart_mcp/server.dart';
import 'package:dart_mcp_server/src/mixins/prompts.dart';
import 'package:test/test.dart';

import '../test_harness.dart';

void main() {
  late TestHarness testHarness;

  // TODO: Use setUpAll, currently this fails due to an apparent TestProcess
  // issue.
  setUp(() async {
    testHarness = await TestHarness.start();
  });

  test('can list prompts', () async {
    final server = testHarness.mcpServerConnection;
    final promptsResult = await server.listPrompts(ListPromptsRequest());
    expect(
      promptsResult.prompts,
      equals([
        isA<GetPromptRequest>().having(
          (p) => p.name,
          'name',
          DashPrompts.flutterDriverUserJourneyTest.name,
        ),
      ]),
    );
  });

  test('can get the flutter driver user journey prompt', () async {
    final server = testHarness.mcpServerConnection;
    final prompt = await server.getPrompt(
      GetPromptRequest(name: DashPrompts.flutterDriverUserJourneyTest.name),
    );
    expect(
      prompt.messages.single,
      isA<PromptMessage>()
          .having((m) => m.role, 'role', Role.user)
          .having(
            (m) => m.content,
            'content',
            equals(DashPrompts.flutterDriverUserJourneyPromptContent),
          ),
    );
  });
}
