// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/server.dart';
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import '../test_harness.dart';

void main() {
  test('discovers resources and prompts from config.yaml', () async {
    final appDir = createApp(
      '''
resources:
  - name: "resource_1"
    title: "Resource 1"
    description: "Resource 1 description"
    path: "resource_1.md"
  - name: "resource_2"
    title: "Resource 2"
    description: "Resource 2 description"
    path: "resource_2.md"
prompts:
  - name: "prompt_1"
    title: "Prompt 1"
    description: "Prompt 1 description"
    path: "prompt_1.md"
  - name: "prompt_2"
    title: "Prompt 2"
    description: "Prompt 2 description"
    path: "prompt_2.md"
''',
      promptContents: {
        'prompt_1.md': 'Hello Prompt 1',
        'prompt_2.md': 'Hello Prompt 2',
      },
      resourceContents: {
        'resource_1.md': 'Hello Resource 1',
        'resource_2.md': 'Hello Resource 2',
      },
    );
    await appDir.create();

    final testHarness = await TestHarness.start(cliArgs: [], inProcess: true);

    final client = testHarness.mcpClient;
    client.addRoot(Root(uri: appDir.io.uri.toString()));
    // Allow the root change notification to be delivered.
    await pumpEventQueue();

    final resourcesResult = await testHarness.mcpServerConnection
        .listResources();
    for (var i = 1; i < 3; i++) {
      final myResource = resourcesResult.resources.firstWhereOrNull(
        (r) => r.name == 'resource_$i',
      );
      expect(myResource, isA<Resource>());
      expect(
        myResource!.uri,
        'package-root:my_app/extension/mcp/resource_$i.md',
      );

      final readResourceResult = await testHarness.mcpServerConnection
          .readResource(ReadResourceRequest(uri: myResource.uri));
      expect(readResourceResult.contents, hasLength(1));
      final content = readResourceResult.contents.first as TextResourceContents;
      expect(content.text, 'Hello Resource $i');
    }

    for (var i = 1; i < 3; i++) {
      final promptsResult = await testHarness.mcpServerConnection.listPrompts();
      expect(
        promptsResult.prompts,
        contains(isA<Prompt>().having((p) => p.name, 'name', 'prompt_$i')),
      );

      final getPromptResult = await testHarness.mcpServerConnection.getPrompt(
        GetPromptRequest(name: 'prompt_$i'),
      );
      final promptContent =
          getPromptResult.messages.first.content as TextContent;
      expect(promptContent.text, 'Hello Prompt $i');
    }
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
      promptContents: {
        'prompt.md': '''
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
      },
    );
    await appDir.create();

    final testHarness = await TestHarness.start(cliArgs: [], inProcess: true);
    final client = testHarness.mcpClient;
    client.addRoot(Root(uri: appDir.io.uri.toString()));
    // Allow the root change notification to be delivered.
    await pumpEventQueue();

    await testHarness.mcpServerConnection.listPrompts();
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
    final appDir = createApp(
      '''
prompts:
  - name: "my_prompt"
    description: "A prompt that has a required argument"
    path: "prompt.md"
    arguments:
      - name: "arg1"
        required: true
''',
      promptContents: {'prompt.md': 'Hello {{arg1}}!'},
    );
    await appDir.create();

    final testHarness = await TestHarness.start(cliArgs: [], inProcess: true);
    final client = testHarness.mcpClient;
    client.addRoot(Root(uri: appDir.io.uri.toString()));
    // Allow the root change notification to be delivered.
    await pumpEventQueue();
    await testHarness.mcpServerConnection.listPrompts();

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

  group('validation', () {
    test('invalid package_config.json is logged', () async {
      final appDir = d.dir('my_app', [
        d.file('pubspec.yaml', '''
name: my_app
environment:
  sdk: ^3.0.0
'''),
        d.dir('.dart_tool', [d.file('package_config.json', '{ bad_json...')]),
      ]);
      await appDir.create();

      final testHarness = await TestHarness.start(cliArgs: [], inProcess: true);
      final client = testHarness.mcpClient;
      final server = testHarness.mcpServerConnection;

      final logFuture = server.onLog.firstWhere(
        (l) =>
            l.level == LoggingLevel.warning &&
            l.data.toString().contains('Error discovering extensions for '),
      );

      client.addRoot(Root(uri: appDir.io.uri.toString()));
      // Allow the root change notification to be delivered.
      await pumpEventQueue();

      await expectLater(logFuture, completes);
    });

    test('invalid resource/prompt yaml is logged', () async {
      final appDir = createApp('''
prompts: "hello"
resources: "hello"
''');
      await appDir.create();

      final testHarness = await TestHarness.start(cliArgs: [], inProcess: true);
      final client = testHarness.mcpClient;
      final server = testHarness.mcpServerConnection;

      final logStream = server.onLog;
      client.addRoot(Root(uri: appDir.io.uri.toString()));
      // Allow the root change notification to be delivered.
      await pumpEventQueue();

      expect(
        logStream,
        emitsInAnyOrder([
          isA<LoggingMessageNotification>()
              .having((l) => l.level, 'level', LoggingLevel.warning)
              .having(
                (l) => l.data,
                'data',
                contains('Package my_app has an invalid prompts config'),
              ),

          isA<LoggingMessageNotification>()
              .having((l) => l.level, 'level', LoggingLevel.warning)
              .having(
                (l) => l.data,
                'data',
                contains('Package my_app has an invalid resources config'),
              ),
        ]),
      );
    });

    test('invalid individual prompt/resource configs are logged', () async {
      final appDir = createApp(
        '''
prompts:
  - name: "valid_prompt"
    path: "prompt_1.md"
  - name: "invalid_prompt_no_path"
  - name: "invalid_prompt_bad_args"
    path: "prompt_1.md"
    arguments:
      - "not_a_map"
resources:
  - name: "valid_resource"
    path: "resource_1.md"
  - name: "invalid_resource_no_path"
''',
        promptContents: {'prompt_1.md': 'Hello'},
        resourceContents: {'resource_1.md': 'World'},
      );
      await appDir.create();

      final testHarness = await TestHarness.start(cliArgs: [], inProcess: true);
      final client = testHarness.mcpClient;
      final server = testHarness.mcpServerConnection;

      final logs = <String>[];
      server.onLog.listen((l) {
        logs.add(l.data.toString());
      });

      client.addRoot(Root(uri: appDir.io.uri.toString()));
      await pumpEventQueue();

      final promptsResult = await server.listPrompts();
      final promptNames = promptsResult.prompts.map((p) => p.name).toList();
      expect(promptNames, contains('valid_prompt'));
      expect(
        promptNames,
        contains('invalid_prompt_bad_args'),
      ); // The prompt loads but without the invalid argument
      expect(promptNames, isNot(contains('invalid_prompt_no_path')));

      final resourcesResult = await server.listResources();
      final resourceNames = resourcesResult.resources
          .map((r) => r.name)
          .toList();
      expect(resourceNames, contains('valid_resource'));
      expect(resourceNames, isNot(contains('invalid_resource_no_path')));

      expect(
        logs,
        containsAll([
          contains(
            'Error loading prompt from package "my_app":\nFormatException: '
            'Expected a string at [prompts][1][path]. Found null.',
          ),
          contains(
            'Invalid prompt argument object from package "my_app": not_a_map',
          ),
          contains(
            'Error loading resource from package "my_app":\nFormatException: '
            'Expected a string at [resources][1][path]. Found null.',
          ),
        ]),
      );
    });
  });

  test(
    'multiple dependencies of the same package uses the latest version',
    () async {
      final appDir = d.dir('my_app', [
        d.dir('app1', [
          d.file('pubspec.yaml', 'name: app1\n'),
          d.dir('.dart_tool', [
            d.file(
              'package_config.json',
              jsonEncode({
                'configVersion': 2,
                'packages': [
                  {
                    'name': 'some_package',
                    'rootUri': '../../some_package_a',
                    'packageUri': 'lib/',
                    'languageVersion': '3.0',
                  },
                  {
                    'name': 'some_package',
                    'rootUri': '../../some_package_b',
                    'packageUri': 'lib/',
                    'languageVersion': '3.0',
                  },
                  {
                    'name': 'some_package',
                    'rootUri': '../../some_package_c',
                    'packageUri': 'lib/',
                    'languageVersion': '3.0',
                  },
                ],
              }),
            ),
          ]),
        ]),
        // We have 3 packages and sandwich the desired one in between them
        // to try and make sure that one isn't the first one encountered
        // and isn't just selected because of that.
        //
        // TODO: can we more reliably affect the load order here?
        d.dir('some_package_a', [
          d.file('pubspec.yaml', 'name: some_package\nversion: 1.0.0\n'),
          d.dir('extension', [
            d.dir('mcp', [
              d.file(
                'config.yaml',
                'prompts:\n  - name: prompt_1_0_0\n    path: prompt.md\n',
              ),
              d.file('prompt.md', 'Hello prompt_1_0_0'),
            ]),
          ]),
        ]),
        d.dir('some_package_b', [
          d.file('pubspec.yaml', 'name: some_package\nversion: 3.0.0\n'),
          d.dir('extension', [
            d.dir('mcp', [
              d.file(
                'config.yaml',
                'prompts:\n  - name: prompt_3_0_0\n    path: prompt.md\n',
              ),
              d.file('prompt.md', 'Hello prompt_3_0_0'),
            ]),
          ]),
        ]),
        d.dir('some_package_c', [
          d.file('pubspec.yaml', 'name: some_package\nversion: 2.0.0\n'),
          d.dir('extension', [
            d.dir('mcp', [
              d.file(
                'config.yaml',
                'prompts:\n  - name: prompt_2_0_0\n    path: prompt.md\n',
              ),
              d.file('prompt.md', 'Hello prompt_2_0_0'),
            ]),
          ]),
        ]),
      ]);

      await appDir.create();

      final testHarness = await TestHarness.start(cliArgs: [], inProcess: true);
      final client = testHarness.mcpClient;
      client.addRoot(Root(uri: appDir.io.uri.toString()));
      await pumpEventQueue();

      final promptsResult = await testHarness.mcpServerConnection.listPrompts();
      final promptNames = promptsResult.prompts.map((p) => p.name).toList();

      expect(promptNames, contains('prompt_3_0_0'));
      expect(
        promptNames,
        isNot(anyOf(contains('prompt_1_0_0'), contains('prompt_2_0_0'))),
      );
    },
    skip: 'TODO(#386): Use the latest version of the package.',
  );
}

d.DirectoryDescriptor createApp(
  String extensionConfig, {
  Map<String, String>? promptContents,
  Map<String, String>? resourceContents,
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
        if (promptContents != null) ...[
          for (final prompt in promptContents.entries)
            d.file(prompt.key, prompt.value),
        ],
        if (resourceContents != null) ...[
          for (final resource in resourceContents.entries)
            d.file(resource.key, resource.value),
        ],
      ]),
    ]),
  ]);
}
