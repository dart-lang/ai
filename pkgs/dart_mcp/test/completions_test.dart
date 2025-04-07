// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:dart_mcp/server.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  test('client can request prompt completions', () async {
    final environment = TestEnvironment(
      TestMCPClient(),
      (c) => TestMCPServerWithCompletions(channel: c),
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

  test('client can request resource completions', () async {
    final environment = TestEnvironment(
      TestMCPClient(),
      (c) => TestMCPServerWithCompletions(channel: c),
    );
    final initializeResult = await environment.initializeServer();
    expect(initializeResult.capabilities.completions, Completions());

    final serverConnection = environment.serverConnection;
    expect(
      (await serverConnection.requestCompletions(
        CompleteRequest(
          ref: TestMCPServerWithCompletions.packageUriTemplateRef,
          argument: CompletionArgument(name: 'package_name', value: 'a'),
        ),
      )).completion.values,
      TestMCPServerWithCompletions.aPackages,
    );
    expect(
      (await serverConnection.requestCompletions(
        CompleteRequest(
          ref: TestMCPServerWithCompletions.packageUriTemplateRef,
          argument: CompletionArgument(name: 'path', value: 'a'),
        ),
      )).completion.values,
      TestMCPServerWithCompletions.packagePaths,
    );
  });
}

final class TestMCPServerWithCompletions extends TestMCPServer
    with CompletionsSupport {
  TestMCPServerWithCompletions({required super.channel});

  @override
  FutureOr<CompleteResult> handleComplete(CompleteRequest request) {
    final ref = request.ref;
    switch (ref) {
      case Reference(isPrompt: true)
          when (ref as PromptReference).name == languagePrompt.name &&
              request.argument.name == languagePrompt.arguments!.single.name &&
              request.argument.value == 'c':
        return CompleteResult(
          completion: Completion(values: cLanguages, hasMore: false),
        );
      case Reference(isResource: true)
          when (ref as ResourceReference).uri == packageUriTemplate.uriTemplate:
        return switch (request.argument) {
          CompletionArgument(name: 'package_name', value: 'a') =>
            CompleteResult(
              completion: Completion(values: aPackages, hasMore: false),
            ),
          CompletionArgument(name: 'path', value: 'a') => CompleteResult(
            completion: Completion(values: packagePaths, hasMore: false),
          ),
          _ =>
            throw ArgumentError.value(
              request.argument,
              'argument',
              'Unrecognized completion argument for URI template '
                  '${packageUriTemplate.uriTemplate}',
            ),
        };
      default:
        throw ArgumentError.value(
          request,
          'request',
          'Unrecognized completion request',
        );
    }
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

  static final packageUriTemplateRef = ResourceReference(
    uri: packageUriTemplate.uriTemplate,
  );
  static final packageUriTemplate = ResourceTemplate(
    uriTemplate: 'package:{package_name}/{path}',
    name: 'PackageUri',
    mimeType: 'text/dart',
    description: 'The package uri of a Dart library',
  );
  static final aPackages = ['async', 'actor', 'add'];
  static final packagePaths = ['async.dart', 'actor.dart', 'add.dart'];
}
