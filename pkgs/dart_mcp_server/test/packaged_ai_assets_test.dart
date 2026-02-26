// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/server.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import 'test_harness.dart';

void main() {
  test('discovers resources and prompts from config.yaml', () async {
    // Scaffold a project with package-config and extensions/mcp/config.yaml
    final appDir = d.dir('my_app', [
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
      d.dir('extensions', [
        d.dir('mcp', [
          d.file('config.yaml', '''
resources:
  - name: "my_resource"
    title: "My Resource"
    description: "My resource description"
    path: "my_resource.md"
prompts:
  - name: "my_prompt"
    title: "My Prompt"
    description: "My prompt description"
    path: "my_prompt.md"
    arguments:
      - "arg1"
'''),
          d.file('my_resource.md', 'Hello Resource'),
          d.file('my_prompt.md', 'Hello Prompt {{arg1}}'),
        ]),
      ]),
    ]);
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
      'package-root://my_app/extensions/mcp/my_resource.md',
    );

    final readResourceResult = await testHarness.mcpServerConnection
        .readResource(ReadResourceRequest(uri: myResource.uri));
    expect(readResourceResult.contents, hasLength(1));
    final content = readResourceResult.contents.first as TextResourceContents;
    expect(content.text, 'Hello Resource');

    final promptsResult = await testHarness.mcpServerConnection.listPrompts();
    expect(promptsResult.prompts, hasLength(greaterThan(0)));
    final myPrompt = promptsResult.prompts.firstWhere(
      (p) => p.name == 'my_prompt',
    );
    expect(myPrompt.arguments, hasLength(1));
    expect(myPrompt.arguments!.first.name, 'arg1');

    final getPromptResult = await testHarness.mcpServerConnection.getPrompt(
      GetPromptRequest(name: 'my_prompt', arguments: {'arg1': 'world'}),
    );
    final promptContent = getPromptResult.messages.first.content as TextContent;
    expect(promptContent.text, 'Hello Prompt world');
  });
}
