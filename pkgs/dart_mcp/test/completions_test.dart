// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:dart_mcp/server.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  test('client can request completions', () async {
    final environment = TestEnvironment(
      TestMCPClient(),
      TestMCPServerWithCompletions.new,
    );
    final initializeResult = await environment.initializeServer();
    expect(initializeResult.capabilities.completions, Completions());

    final serverConnection = environment.serverConnection;
    expect(
      (await serverConnection.requestCompletions(
        CompleteRequest(
          ref: TestMCPServerWithCompletions.languagePromptRef,
          argument: CompletionArgument(
            name:
                TestMCPServerWithCompletions
                    .languagePrompt
                    .arguments!
                    .single
                    .name,
            value: 'c',
          ),
        ),
      )).completion.values,
      TestMCPServerWithCompletions.cLanguages,
    );
  });
}

final class TestMCPServerWithCompletions extends TestMCPServer
    with CompletionsSupport {
  TestMCPServerWithCompletions(super.channel) : super();

  @override
  FutureOr<CompleteResult> handleComplete(CompleteRequest request) {
    assert(request.ref.isPrompt);
    final promptRef = request.ref as PromptReference;
    assert(promptRef.name == languagePrompt.name);
    assert(request.argument.name == languagePrompt.arguments!.single.name);
    assert(request.argument.value == 'c');
    return CompleteResult(
      completion: Completion(values: cLanguages, hasMore: false),
    );
  }

  static final languagePromptRef = PromptReference(name: languagePrompt.name);
  static final languagePrompt = Prompt(
    name: 'CodeGenerator',
    description: 'generates code in a given language',
    arguments: [
      PromptArgument(
        name: 'language',
        description: 'the language to generate code in',
        required: true,
      ),
    ],
  );
  static final cLanguages = ['c', 'c++', 'c#'];
}
