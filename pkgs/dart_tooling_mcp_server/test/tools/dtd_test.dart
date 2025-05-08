// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:async/async.dart';
import 'package:dart_mcp/server.dart';
import 'package:dart_tooling_mcp_server/src/mixins/dtd.dart';
import 'package:dart_tooling_mcp_server/src/utils/constants.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

import '../test_harness.dart';

void main() {
  late TestHarness testHarness;

  group('dart tooling daemon tools', () {
    group('[compiled server]', () {
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

    group('[in process]', () {
      setUp(() async {
        DartToolingDaemonSupport.debugAwaitVmServiceDisposal = true;
        addTearDown(
          () => DartToolingDaemonSupport.debugAwaitVmServiceDisposal = false,
        );

        testHarness = await TestHarness.start(inProcess: true);
        await testHarness.connectToDtd();
      });

      group('$VmService management', () {
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
          await pumpEventQueue();
          expect(server.activeVmServices.length, 1);

          await testHarness.stopDebugSession(debugSession);
          await pumpEventQueue();
          expect(server.activeVmServices, isEmpty);
        });
      });

      group('get selected widget', () {
        test('when a selected widget exists', () async {
          final server = testHarness.serverConnectionPair.server!;
          final tools =
              (await testHarness.mcpServerConnection.listTools()).tools;

          await testHarness.startDebugSession(
            counterAppPath,
            'lib/main.dart',
            isFlutter: true,
          );
          await server.updateActiveVmServices();

          final getWidgetTreeTool = tools.singleWhere(
            (t) => t.name == DartToolingDaemonSupport.getWidgetTreeTool.name,
          );
          final getWidgetTreeResult = await testHarness.callToolWithRetry(
            CallToolRequest(name: getWidgetTreeTool.name),
          );

          // Select the first child of the [root] widget.
          final widgetTree =
              jsonDecode(
                    (getWidgetTreeResult.content.first as TextContent).text,
                  )
                  as Map<String, Object?>;
          final children = widgetTree['children'] as List<Object?>;
          final firstWidgetId =
              (children.first as Map<String, Object?>)['valueId'];
          final appVmService = await server.activeVmServices.values.first;
          final vm = await appVmService.getVM();
          await appVmService.callServiceExtension(
            'ext.flutter.inspector.setSelectionById',
            isolateId: vm.isolates!.first.id,
            args: {
              'objectGroup': DartToolingDaemonSupport.inspectorObjectGroup,
              'arg': firstWidgetId,
            },
          );

          // Confirm we can get the selected widget from the MCP tool.
          final getSelectedWidgetTool = tools.singleWhere(
            (t) =>
                t.name == DartToolingDaemonSupport.getSelectedWidgetTool.name,
          );
          final getSelectedWidgetResult = await testHarness.callToolWithRetry(
            CallToolRequest(name: getSelectedWidgetTool.name),
          );
          expect(getSelectedWidgetResult.isError, isNot(true));
          expect(
            (getSelectedWidgetResult.content.first as TextContent).text,
            contains('MyApp'),
          );
        });

        test('when there is no selected widget', () async {
          await testHarness.startDebugSession(
            counterAppPath,
            'lib/main.dart',
            isFlutter: true,
          );
          final tools =
              (await testHarness.mcpServerConnection.listTools()).tools;
          final getSelectedWidgetTool = tools.singleWhere(
            (t) =>
                t.name == DartToolingDaemonSupport.getSelectedWidgetTool.name,
          );
          final getSelectedWidgetResult = await testHarness.callToolWithRetry(
            CallToolRequest(name: getSelectedWidgetTool.name),
          );

          expect(getSelectedWidgetResult.isError, isNot(true));
          expect(
            (getSelectedWidgetResult.content.first as TextContent).text,
            contains('No Widget selected.'),
          );
        });
      });

      group('runtime errors', () {
        final errorCountRegex = RegExp(r'Found \d+ errors?:');

        setUp(() async {
          await testHarness.startDebugSession(
            counterAppPath,
            'lib/main.dart',
            isFlutter: true,
            args: ['--dart-define=include_layout_error=true'],
          );
        });

        test('can be read and cleared using the tool', () async {
          final tools =
              (await testHarness.mcpServerConnection.listTools()).tools;
          final runtimeErrorsTool = tools.singleWhere(
            (t) => t.name == DartToolingDaemonSupport.getRuntimeErrorsTool.name,
          );
          late CallToolResult runtimeErrorsResult;

          // Give the errors at most a second to come through.
          var count = 0;
          while (true) {
            runtimeErrorsResult = await testHarness.callToolWithRetry(
              CallToolRequest(
                name: runtimeErrorsTool.name,
                arguments: {'clearRuntimeErrors': true},
              ),
            );
            expect(runtimeErrorsResult.isError, isNot(true));
            final firstText =
                (runtimeErrorsResult.content.first as TextContent).text;
            if (errorCountRegex.hasMatch(firstText)) {
              break;
            } else if (++count > 10) {
              fail('No errors found, expected at least one');
            } else {
              await Future<void>.delayed(const Duration(milliseconds: 100));
            }
          }
          expect(
            (runtimeErrorsResult.content[1] as TextContent).text,
            contains('A RenderFlex overflowed by'),
          );

          // We cleared the errors in the previous call, shouldn't see any here.
          final nextResult = await testHarness.callToolWithRetry(
            CallToolRequest(name: runtimeErrorsTool.name),
          );
          expect(
            (nextResult.content.first as TextContent).text,
            contains('No runtime errors found'),
          );

          // Trigger a hot reload, should see the error again.
          await testHarness.callToolWithRetry(
            CallToolRequest(name: DartToolingDaemonSupport.hotReloadTool.name),
          );

          final finalRuntimeErrorsResult = await testHarness.callToolWithRetry(
            CallToolRequest(name: runtimeErrorsTool.name),
          );
          expect(
            (finalRuntimeErrorsResult.content.first as TextContent).text,
            contains(errorCountRegex),
          );
          expect(
            (finalRuntimeErrorsResult.content[1] as TextContent).text,
            contains('A RenderFlex overflowed by'),
          );
        });

        test('can be read and subscribed to as a resource', () async {
          final serverConnection = testHarness.mcpServerConnection;
          final onResourceListChanged =
              serverConnection.resourceListChanged.first;
          var resources =
              (await serverConnection.listResources(
                ListResourcesRequest(),
              )).resources;
          if (resources.runtimeErrors.isEmpty) {
            await onResourceListChanged;
            resources =
                (await serverConnection.listResources(
                  ListResourcesRequest(),
                )).resources;
          }
          final resource = resources.runtimeErrors.single;

          final resourceUpdatedQueue = StreamQueue(
            serverConnection.resourceUpdated,
          );
          await serverConnection.subscribeResource(
            SubscribeRequest(uri: resource.uri),
          );
          await pumpEventQueue();
          var originalContents =
              (await serverConnection.readResource(
                ReadResourceRequest(uri: resource.uri),
              )).contents;
          final overflowMatcher = isA<TextResourceContents>().having(
            (c) => c.text,
            'text',
            contains('A RenderFlex overflowed by'),
          );
          // If we haven't seen errors initially, then listen for updates and
          // re-read the resource.
          if (originalContents.isEmpty) {
            await resourceUpdatedQueue.next;
            originalContents =
                (await serverConnection.readResource(
                  ReadResourceRequest(uri: resource.uri),
                )).contents;
          }
          // Sometimes we get this error logged multiple times
          expect(originalContents.first, overflowMatcher);
          await pumpEventQueue();

          await testHarness.callToolWithRetry(
            CallToolRequest(name: DartToolingDaemonSupport.hotReloadTool.name),
          );

          expect(
            await resourceUpdatedQueue.next,
            isA<ResourceUpdatedNotification>().having(
              (n) => n.uri,
              ParameterNames.uri,
              resource.uri,
            ),
          );

          // We should see additional errors (but the exact number is variable).
          final newContents =
              (await serverConnection.readResource(
                ReadResourceRequest(uri: resource.uri),
              )).contents;
          expect(newContents.length, greaterThan(originalContents.length));
          expect(newContents.last, overflowMatcher);

          // Now hot reload but clear previous errors, should see fewer errors
          // than before after this.
          await testHarness.callToolWithRetry(
            CallToolRequest(
              name: DartToolingDaemonSupport.hotReloadTool.name,
              arguments: {'clearRuntimeErrors': true},
            ),
          );

          expect(
            await resourceUpdatedQueue.next,
            isA<ResourceUpdatedNotification>().having(
              (n) => n.uri,
              ParameterNames.uri,
              resource.uri,
            ),
          );

          final finalContents =
              (await serverConnection.readResource(
                ReadResourceRequest(uri: resource.uri),
              )).contents;
          expect(finalContents.length, lessThan(newContents.length));
          expect(finalContents.last, overflowMatcher);
        });
      });

      group('getActiveLocationTool', () {
        test(
          'returns "no location" if DTD connected but no event received',
          () async {
            final result = await testHarness.callToolWithRetry(
              CallToolRequest(
                name: DartToolingDaemonSupport.getActiveLocationTool.name,
              ),
            );
            expect(
              (result.content.first as TextContent).text,
              'No active location reported by the editor yet.',
            );
          },
        );

        test('returns active location after event', () async {
          final fakeEditor = testHarness.fakeEditorExtension;

          // Simulate activeLocationChanged event
          final fakeEvent = {'someData': 'isHere'};
          await fakeEditor.dtd.postEvent(
            'Editor',
            'activeLocationChanged',
            fakeEvent,
          );
          await pumpEventQueue();

          final result = await testHarness.callToolWithRetry(
            CallToolRequest(
              name: DartToolingDaemonSupport.getActiveLocationTool.name,
            ),
          );
          expect(
            (result.content.first as TextContent).text,
            jsonEncode(fakeEvent),
          );
        });
      });
    });
  });
}

extension on Iterable<Resource> {
  Iterable<Resource> get runtimeErrors => where(
    (r) => r.uri.startsWith(DartToolingDaemonSupport.runtimeErrorsScheme),
  );
}
