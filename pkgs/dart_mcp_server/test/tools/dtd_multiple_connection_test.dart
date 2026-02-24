import 'package:dart_mcp/server.dart';

import 'package:dart_mcp_server/src/utils/names.dart';
import 'package:test/test.dart';

import '../test_harness.dart';

void main() {
  late TestHarness testHarness;

  group('multiple dtd connections', () {
    setUp(() async {
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
          name: ToolNames.disconnectDartToolingDaemon.name,
          arguments: {
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

      // Give some time for services to register
      await Future<void>.delayed(const Duration(milliseconds: 500));

      final listResult = await testHarness.callTool(
        CallToolRequest(name: ToolNames.listConnectedApps.name, arguments: {}),
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
  });
}
