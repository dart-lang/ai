// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:dart_mcp_server/src/mixins/dtd.dart';

import 'package:dart_mcp_server/src/utils/names.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import '../test_harness.dart';

void main() {
  late TestHarness testHarness;

  group('multiple dtd connections', () {
    setUp(() async {
      // Ensure the sandbox is created before the test harness, so its teardown
      // happens after the harness is shut down.
      d.sandbox;
      testHarness = await TestHarness.start();
    });

    test('connects to multiple DTDs', () async {
      await testHarness.connectToDtd();

      final secondEditorExtension = await FakeEditorExtension.connect(
        testHarness.sdk,
      );
      addTearDown(secondEditorExtension.shutdown);

      final result = await testHarness.connectToDtd(
        dtdUri: secondEditorExtension.dtdUri,
      );

      expect(result.isError, isNot(true));
      expect(
        (result.content.first as TextContent).text,
        contains('Connection succeeded'),
      );
    });

    test('can disconnect from a specific DTD', () async {
      await testHarness.connectToDtd();
      final secondEditorExtension = await FakeEditorExtension.connect(
        testHarness.sdk,
      );
      addTearDown(secondEditorExtension.shutdown);

      await testHarness.connectToDtd(dtdUri: secondEditorExtension.dtdUri);

      final result = await testHarness.callTool(
        CallToolRequest(
          name: ToolNames.dtd.name,
          arguments: {
            ParameterNames.command: DtdCommand.disconnect,
            ParameterNames.uri: testHarness.fakeEditorExtension!.dtdUri,
          },
        ),
      );
      expect(result.isError, isNot(true));
      expect(
        (result.content.first as TextContent).text,
        contains('Disconnected'),
      );

      // Verify we can connect again (meaning we successfully disconnected)
      final reconnectResult = await testHarness.connectToDtd();
      expect(reconnectResult.isError, isNot(true));
      expect(
        (reconnectResult.content.first as TextContent).text,
        contains('Connection succeeded'),
      );
    });

    test('lists connected apps and uses appUri', () async {
      await testHarness.connectToDtd();
      final session1 = await testHarness.startDebugSession(
        counterAppPath,
        'lib/main.dart',
        isFlutter: true,
      );
      addTearDown(() => testHarness.stopDebugSession(session1));

      // Start a second DTD and and app associated with it.
      final secondEditorExtension = await FakeEditorExtension.connect(
        testHarness.sdk,
      );
      addTearDown(secondEditorExtension.shutdown);
      await testHarness.connectToDtd(dtdUri: secondEditorExtension.dtdUri);

      final session2 = await testHarness.startDebugSession(
        dartCliAppsPath,
        'bin/infinite_wait.dart',
        isFlutter: false,
        editorExtension: secondEditorExtension,
      );
      addTearDown(
        () => testHarness.stopDebugSession(
          session2,
          editorExtension: secondEditorExtension,
        ),
      );

      final listResult = await testHarness.callToolWithRetry(
        CallToolRequest(
          name: ToolNames.dtd.name,
          arguments: {ParameterNames.command: DtdCommand.listConnectedApps},
        ),
        retryUntil: (result) =>
            (result.structuredContent![ParameterNames.apps] as List).length ==
            2,
      );
      expect(listResult.isError, isNot(true));
      final structured = listResult.structuredContent;
      expect(structured, isNotNull);
      final connectedApps = (structured![ParameterNames.apps] as List)
          .cast<String>();
      expect(connectedApps, hasLength(2));
      for (final uri in connectedApps) {
        expect(Uri.tryParse(uri), isNotNull, reason: 'App ID should be a URI');
      }

      // Call tool without appUri (should fail)
      final failResult = await testHarness.callTool(
        CallToolRequest(name: ToolNames.hotReload.name, arguments: {}),
        expectError: true,
      );
      expect(failResult.isError, isTrue);
      expect(
        (failResult.content.first as TextContent).text,
        contains('Multiple apps connected'),
      );

      // Call tool WITH appUri (should succeed)
      for (final appUri in connectedApps) {
        final result = await testHarness.callTool(
          CallToolRequest(
            name: ToolNames.hotReload.name,
            arguments: {ParameterNames.appUri: appUri},
          ),
        );
        expect(
          (result.content.first as TextContent).text,
          contains('Hot reload succeeded.'),
        );
      }
    });

    test(
      'can get runtime errors from multiple apps using appUri',
      () async {
        await testHarness.connectToDtd();

        await d.dir('dart_app_1', [
          d.dir('bin', [
            d.file('main.dart', '''
import 'dart:io';
void main() async {
  stderr.writeln('error from app 1');
  while (true) {
    await Future.delayed(Duration(seconds: 1));
  }
}
'''),
          ]),
        ]).create();
        final session1 = await testHarness.startDebugSession(
          p.join(d.sandbox, 'dart_app_1'),
          'bin/main.dart',
          isFlutter: false,
        );
        addTearDown(() => testHarness.stopDebugSession(session1));

        final secondEditorExtension = await FakeEditorExtension.connect(
          testHarness.sdk,
        );
        addTearDown(secondEditorExtension.shutdown);
        await testHarness.connectToDtd(dtdUri: secondEditorExtension.dtdUri);

        await d.dir('dart_app_2', [
          d.dir('bin', [
            d.file('main.dart', '''
import 'dart:io';
void main() async {
  stderr.writeln('error from app 2');
  while (true) {
    await Future.delayed(Duration(seconds: 1));
  }
}
'''),
          ]),
        ]).create();
        final session2 = await testHarness.startDebugSession(
          p.join(d.sandbox, 'dart_app_2'),
          'bin/main.dart',
          isFlutter: false,
          editorExtension: secondEditorExtension,
        );
        addTearDown(
          () => testHarness.stopDebugSession(
            session2,
            editorExtension: secondEditorExtension,
          ),
        );

        final listResult = await testHarness.callToolWithRetry(
          CallToolRequest(
            name: ToolNames.dtd.name,
            arguments: {ParameterNames.command: DtdCommand.listConnectedApps},
          ),
          retryUntil: (result) =>
              (result.structuredContent![ParameterNames.apps] as List).length ==
              2,
        );
        final connectedApps =
            (listResult.structuredContent![ParameterNames.apps] as List)
                .cast<String>();
        expect(connectedApps, hasLength(2));

        // Verify errors for App 1
        final errors1 = await testHarness.callToolWithRetry(
          CallToolRequest(
            name: ToolNames.getRuntimeErrors.name,
            arguments: {ParameterNames.appUri: session1.vmServiceUri},
          ),
        );
        expect(
          (errors1.content[1] as TextContent).text,
          contains('error from app 1'),
        );

        // Verify errors for App 2
        final errors2 = await testHarness.callToolWithRetry(
          CallToolRequest(
            name: ToolNames.getRuntimeErrors.name,
            arguments: {ParameterNames.appUri: session2.vmServiceUri},
          ),
          retryUntil: (result) => result.content.length > 1,
        );
        expect(
          (errors2.content[1] as TextContent).text,
          contains('error from app 2'),
        );
      },
      skip: Platform.isWindows
          ? 'https://github.com/dart-lang/ai/issues/407'
          : false,
    );
  });
}
