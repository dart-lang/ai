// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/server.dart';
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import '../test_harness.dart';

void main() {
  test('discovers resources and prompts from config.yaml', () async {
    // Scaffold a project with package-config and extensions/mcp/config.yaml
    final appDir = createApp(
      '''
resources:
  - name: "my_resource"
    title: "My Resource"
    description: "My resource description"
    path: "resource.md"
prompts:
  - name: "my_prompt"
    title: "My Prompt"
    description: "My prompt description"
    path: "prompt.md"
''',
      promptContent: 'Hello Prompt',
      resourceContent: 'Hello Resource',
    );
    await appDir.create();

    final testHarness = await TestHarness.start(cliArgs: [], inProcess: true);

    // Initialize the client so the roots can be discovered.
    final client = testHarness.mcpClient;
    client.addRoot(Root(uri: appDir.io.uri.toString()));

    // Give it a moment to process the listRoots call and discover assets
    await Future<void>.delayed(const Duration(seconds: 1));

    final resourcesResult = await testHarness.mcpServerConnection
        .listResources();
    expect(resourcesResult.resources, hasLength(greaterThan(0)));
    final myResource = resourcesResult.resources.firstWhere(
      (r) => r.name == 'my_resource',
    );
    expect(
      myResource.uri,
      'package-root:my_app/extension/mcp/resource.md',
    );

    final readResourceResult = await testHarness.mcpServerConnection
        .readResource(ReadResourceRequest(uri: myResource.uri));
    expect(readResourceResult.contents, hasLength(1));
    final content = readResourceResult.contents.first as TextResourceContents;
    expect(content.text, 'Hello Resource');

    final promptsResult = await testHarness.mcpServerConnection.listPrompts();
    expect(promptsResult.prompts, hasLength(2));
    expect(
      promptsResult.prompts,
      contains(isA<Prompt>().having((p) => p.name, 'name', 'my_prompt')),
    );

    final getPromptResult = await testHarness.mcpServerConnection.getPrompt(
      GetPromptRequest(name: 'my_prompt'),
    );
    final promptContent = getPromptResult.messages.first.content as TextContent;
    expect(promptContent.text, 'Hello Prompt');
  });

  test('renders mustache templates for prompts with arguments', () async {
    final appDir = createApp(
      '''
prompts:
  - name: "my_prompt"
    description: "A prompt that uses arguments and mustache"
    path: "prompt.md"
    arguments:
      - name: "arg1"
      - name: "arg2"
      - name: "arg3"
''',
      promptContent: '''
Hello {{arg1}}!
{{#arg2}}
Arg2 was passed {{arg2}}.
{{/arg2}}
{{^arg2}}
Arg2 was not passed.
{{/arg2}}
{{#arg3}}
Arg3 was passed {{arg3}}.
{{/arg3}}
{{^arg3}}
Arg3 was not passed.
{{/arg3}}
''',
    );
    await appDir.create();

    final testHarness = await TestHarness.start(cliArgs: [], inProcess: true);
    final client = testHarness.mcpClient;
    client.addRoot(Root(uri: appDir.io.uri.toString()));

    // Wait for discovery
    await Future<void>.delayed(const Duration(seconds: 1));

    final getPromptResult = await testHarness.mcpServerConnection.getPrompt(
      GetPromptRequest(
        name: 'my_prompt',
        arguments: {'arg1': 'World', 'arg2': 'arg2 value'},
      ),
    );
    final promptContent = getPromptResult.messages.first.content as TextContent;
    expect(promptContent.text, contains('Hello World!'));
    expect(promptContent.text, contains('Arg2 was passed arg2 value.'));
    expect(promptContent.text, isNot(contains('Arg2 was not passed.')));
    expect(promptContent.text, isNot(contains('Arg3 was passed arg3 value.')));
    expect(promptContent.text, contains('Arg3 was not passed.'));
  });

  test('required arguments must be passed', () async {
    final appDir = createApp('''
prompts:
  - name: "my_prompt"
    description: "A prompt that has a required argument"
    path: "prompt.md"
    arguments:
      - name: "arg1"
        required: true
''', promptContent: 'Hello {{arg1}}!');
    await appDir.create();

    final testHarness = await TestHarness.start(cliArgs: [], inProcess: true);
    final client = testHarness.mcpClient;
    client.addRoot(Root(uri: appDir.io.uri.toString()));

    // Wait for discovery
    await Future<void>.delayed(const Duration(seconds: 1));

    expect(
      () => testHarness.mcpServerConnection.getPrompt(
        GetPromptRequest(name: 'my_prompt'),
      ),
      throwsA(
        isA<RpcException>().having(
          (e) => e.message,
          'message',
          contains('Missing required prompt argument: arg1'),
        ),
      ),
    );

  });
}

d.DirectoryDescriptor createApp(
  String extensionConfig, {
  String? promptContent,
  String? resourceContent,
}) {
  return d.dir('my_app', [
    d.file('pubspec.yaml', '''
name: my_app
environment:
  sdk: ^3.0.0
'''),
    d.dir('.dart_tool', [
      d.file(
        'package_config.json',
        jsonEncode({
          'configVersion': 2,
          'packages': [
            {
              'name': 'my_app',
              'rootUri': '../',
              'packageUri': 'lib/',
              'languageVersion': '3.0',
            },
          ],
        }),
      ),
    ]),
    d.dir('extension', [
      d.dir('mcp', [
        d.file('config.yaml', extensionConfig),
        if (promptContent != null) d.file('prompt.md', promptContent),
        if (resourceContent != null) d.file('resource.md', resourceContent),
      ]),
    ]),
  ]);
}
