// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dart_mcp/server.dart';
import 'package:dart_tooling_mcp_server/src/mixins/dtd.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

import '../test_harness.dart';

void main() {
  late TestHarness testHarness;

  group('dart tooling daemon tools', () {
    // TODO: Use setUpAll, currently this fails due to an apparent TestProcess
    // issue.
    setUp(() async {
      testHarness = await TestHarness.start();
      await testHarness.connectToDtd();
    });

    test('can take a screenshot', () async {
      await testHarness.startDebugSession(
        counterAppPath,
        'lib/main.dart',
        isFlutter: true,
      );
      final tools = (await testHarness.mcpServerConnection.listTools()).tools;
      final screenshotTool = tools.singleWhere(
        (t) => t.name == DartToolingDaemonSupport.screenshotTool.name,
      );
      final screenshotResult = await testHarness.callToolWithRetry(
        CallToolRequest(name: screenshotTool.name),
      );
      expect(screenshotResult.content.single, {
        'data': anything,
        'mimeType': 'image/png',
        'type': ImageContent.expectedType,
      });
    });

    test('can perform a hot reload', () async {
      await testHarness.startDebugSession(
        counterAppPath,
        'lib/main.dart',
        isFlutter: true,
      );
      final tools = (await testHarness.mcpServerConnection.listTools()).tools;
      final hotReloadTool = tools.singleWhere(
        (t) => t.name == DartToolingDaemonSupport.hotReloadTool.name,
      );
      final hotReloadResult = await testHarness.callToolWithRetry(
        CallToolRequest(name: hotReloadTool.name),
      );

      expect(hotReloadResult.isError, isNot(true));
      expect(hotReloadResult.content, [
        TextContent(text: 'Hot reload succeeded.'),
      ]);
    });

    test('can get runtime errors', () async {
      await testHarness.startDebugSession(
        counterAppPath,
        'lib/main.dart',
        isFlutter: true,
        args: ['--dart-define=include_layout_error=true'],
      );
      final tools = (await testHarness.mcpServerConnection.listTools()).tools;
      final runtimeErrorsTool = tools.singleWhere(
        (t) => t.name == DartToolingDaemonSupport.getRuntimeErrorsTool.name,
      );
      final runtimeErrorsResult = await testHarness.callToolWithRetry(
        CallToolRequest(name: runtimeErrorsTool.name),
      );

      expect(runtimeErrorsResult.isError, isNot(true));
      final errorCountRegex = RegExp(r'Found \d+ errors?:');
      expect(
        (runtimeErrorsResult.content.first as TextContent).text,
        contains(errorCountRegex),
      );
      expect(
        (runtimeErrorsResult.content[1] as TextContent).text,
        contains('A RenderFlex overflowed by'),
      );
    });

    test('can get the widget tree', () async {
      await testHarness.startDebugSession(
        counterAppPath,
        'lib/main.dart',
        isFlutter: true,
      );
      final tools = (await testHarness.mcpServerConnection.listTools()).tools;
      final getWidgetTreeTool = tools.singleWhere(
        (t) => t.name == DartToolingDaemonSupport.getWidgetTreeTool.name,
      );
      final getWidgetTreeResult = await testHarness.callToolWithRetry(
        CallToolRequest(name: getWidgetTreeTool.name),
      );

      expect(getWidgetTreeResult.isError, isNot(true));
      expect(
        (getWidgetTreeResult.content.first as TextContent).text,
        contains('MyHomePage'),
      );
    });
  });

  group('$VmService management', () {
    setUp(() async {
      DartToolingDaemonSupport.debugAwaitVmServiceDisposal = true;
      addTearDown(
        () => DartToolingDaemonSupport.debugAwaitVmServiceDisposal = false,
      );

      testHarness = await TestHarness.start(inProcess: true);
      await testHarness.connectToDtd();
    });

    test('persists vm services', () async {
      final server = testHarness.serverConnectionPair.server!;
      expect(server.activeVmServices, isEmpty);

      await testHarness.startDebugSession(
        counterAppPath,
        'lib/main.dart',
        isFlutter: true,
      );
      await server.updateActiveVmServices();
      expect(server.activeVmServices.length, 1);

      // Re-uses existing VM Service when available.
      final originalVmService = server.activeVmServices.values.single;
      await server.updateActiveVmServices();
      expect(server.activeVmServices.length, 1);
      expect(originalVmService, server.activeVmServices.values.single);

      await testHarness.startDebugSession(
        counterAppPath,
        'lib/main.dart',
        isFlutter: true,
      );
      await server.updateActiveVmServices();
      expect(server.activeVmServices.length, 2);
    });

    test('automatically removes vm services upon shutdown', () async {
      final server = testHarness.serverConnectionPair.server!;
      expect(server.activeVmServices, isEmpty);

      final debugSession = await testHarness.startDebugSession(
        counterAppPath,
        'lib/main.dart',
        isFlutter: true,
      );
      await server.updateActiveVmServices();
      expect(server.activeVmServices.length, 1);

      await testHarness.stopDebugSession(debugSession);
      await server.updateActiveVmServices();
      expect(server.activeVmServices, isEmpty);
    });
  });
}
