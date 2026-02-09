// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:async/async.dart';
import 'package:dart_mcp/server.dart';
import 'package:dart_mcp_server/src/mixins/dtd.dart';
import 'package:dart_mcp_server/src/server.dart';
import 'package:dart_mcp_server/src/utils/analytics.dart';
import 'package:dart_mcp_server/src/utils/names.dart';
import 'package:devtools_shared/devtools_shared.dart';
import 'package:dtd/dtd.dart';
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:test/test.dart';
import 'package:unified_analytics/testing.dart';
import 'package:unified_analytics/unified_analytics.dart' as ua;
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

      group('flutter tests', () {
        test('can get the widget tree', () async {
          await testHarness.startDebugSession(
            counterAppPath,
            'lib/main.dart',
            isFlutter: true,
          );
          final tools =
              (await testHarness.mcpServerConnection.listTools()).tools;
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

        test('can perform a hot reload', () async {
          await testHarness.startDebugSession(
            counterAppPath,
            'lib/main.dart',
            isFlutter: true,
          );
          final tools =
              (await testHarness.mcpServerConnection.listTools()).tools;
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

        test('can perform a hot restart', () async {
          await testHarness.startDebugSession(
            counterAppPath,
            'lib/main.dart',
            isFlutter: true,
          );
          final tools =
              (await testHarness.mcpServerConnection.listTools()).tools;
          final hotRestartTool = tools.singleWhere(
            (t) => t.name == DartToolingDaemonSupport.hotRestartTool.name,
          );
          final hotRestartResult = await testHarness.callToolWithRetry(
            CallToolRequest(name: hotRestartTool.name),
          );

          expect(hotRestartResult.isError, isNot(true));
          expect(hotRestartResult.content, [
            TextContent(text: 'Hot restart succeeded.'),
          ]);
        });
      });

      group('sampling service extension', () {
        List<String> extractResponse(DTDResponse response) {
          final responseContent =
              response.result['content'] as Map<String, Object?>;
          return (responseContent['text'] as String).split('\n');
        }

        Future<String> getSamplingServiceName(
          DartToolingDaemon dtdClient,
        ) async {
          final services = await dtdClient.getRegisteredServices();
          final samplingService = services.clientServices.firstWhere(
            (s) => s.name.startsWith(McpServiceConstants.serviceName),
          );
          return samplingService.name;
        }

        test('is registered with correct name format', () async {
          final dtdClient = testHarness.fakeEditorExtension!.dtd;
          final services = await dtdClient.getRegisteredServices();
          final samplingService = services.clientServices.first;
          final sanitizedClientName =
              'test_client_for_the_dart_tooling_mcp_server';
          expect(
            samplingService.name,
            startsWith(
              '${McpServiceConstants.serviceName}_${sanitizedClientName}_',
            ),
          );
          // Check that the service name ends with an 8-character ID.
          expect(samplingService.name, matches(RegExp(r'[a-f0-9]{8}$')));
          expect(
            samplingService.methods,
            contains(McpServiceConstants.samplingRequest),
          );
        });

        test('can make a sampling request with text', () async {
          final dtdClient = testHarness.fakeEditorExtension!.dtd;
          final samplingServiceName = await getSamplingServiceName(dtdClient);
          final response = await dtdClient.call(
            samplingServiceName,
            McpServiceConstants.samplingRequest,
            params: {
              'messages': [
                {
                  'role': 'user',
                  'content': {'type': 'text', 'text': 'hello world'},
                },
              ],
              'maxTokens': 512,
            },
          );
          expect(extractResponse(response), [
            'TOKENS: 512',
            '[user] hello world',
          ]);
        });

        test('can make a sampling request with an image', () async {
          final dtdClient = testHarness.fakeEditorExtension!.dtd;
          final samplingServiceName = await getSamplingServiceName(dtdClient);
          final response = await dtdClient.call(
            samplingServiceName,
            McpServiceConstants.samplingRequest,
            params: {
              'messages': [
                {
                  'role': 'user',
                  'content': {
                    'type': 'image',
                    'data': 'fake-data',
                    'mimeType': 'image/png',
                  },
                },
              ],
              'maxTokens': 256,
            },
          );
          expect(extractResponse(response), [
            'TOKENS: 256',
            '[user] image/png',
          ]);
        });

        test('can make a sampling request with audio', () async {
          final dtdClient = testHarness.fakeEditorExtension!.dtd;
          final samplingServiceName = await getSamplingServiceName(dtdClient);
          final response = await dtdClient.call(
            samplingServiceName,
            McpServiceConstants.samplingRequest,
            params: {
              'messages': [
                {
                  'role': 'user',
                  'content': {
                    'type': 'audio',
                    'data': 'fake-data',
                    'mimeType': 'audio',
                  },
                },
              ],
              'maxTokens': 256,
            },
          );
          expect(extractResponse(response), ['TOKENS: 256', '[user] audio']);
        });

        test('can make a sampling request with an embedded resource', () async {
          final dtdClient = testHarness.fakeEditorExtension!.dtd;
          final samplingServiceName = await getSamplingServiceName(dtdClient);
          final response = await dtdClient.call(
            samplingServiceName,
            McpServiceConstants.samplingRequest,
            params: {
              'messages': [
                {
                  'role': 'user',
                  'content': {
                    'type': 'resource',
                    'resource': {'uri': 'www.google.com', 'text': 'Google'},
                  },
                },
              ],
              'maxTokens': 256,
            },
          );
          expect(extractResponse(response), [
            'TOKENS: 256',
            '[user] www.google.com',
          ]);
        });

        test('can make a sampling request with mixed content', () async {
          final dtdClient = testHarness.fakeEditorExtension!.dtd;
          final samplingServiceName = await getSamplingServiceName(dtdClient);
          final response = await dtdClient.call(
            samplingServiceName,
            McpServiceConstants.samplingRequest,
            params: {
              'messages': [
                {
                  'role': 'user',
                  'content': {'type': 'text', 'text': 'hello world'},
                },
                {
                  'role': 'user',
                  'content': {
                    'type': 'image',
                    'data': 'fake-data',
                    'mimeType': 'image/jpeg',
                  },
                },
              ],
              'maxTokens': 128,
            },
          );
          expect(extractResponse(response), [
            'TOKENS: 128',
            '[user] hello world',
            '[user] image/jpeg',
          ]);
        });

        test('can handle user and assistant messages', () async {
          final dtdClient = testHarness.fakeEditorExtension!.dtd;
          final samplingServiceName = await getSamplingServiceName(dtdClient);
          final response = await dtdClient.call(
            samplingServiceName,
            McpServiceConstants.samplingRequest,
            params: {
              'messages': [
                {
                  'role': 'user',
                  'content': {'type': 'text', 'text': 'Hi! I have a question.'},
                },
                {
                  'role': 'assistant',
                  'content': {'type': 'text', 'text': 'What is your question?'},
                },
                {
                  'role': 'user',
                  'content': {'type': 'text', 'text': 'How big is the sun?'},
                },
              ],
              'maxTokens': 512,
            },
          );
          expect(extractResponse(response), [
            'TOKENS: 512',
            '[user] Hi! I have a question.',
            '[assistant] What is your question?',
            '[user] How big is the sun?',
          ]);
        });

        test('forwards all messages, even those with unknown types', () async {
          final dtdClient = testHarness.fakeEditorExtension!.dtd;
          final samplingServiceName = await getSamplingServiceName(dtdClient);
          final response = await dtdClient.call(
            samplingServiceName,
            McpServiceConstants.samplingRequest,
            params: {
              'messages': [
                {
                  'role': 'user',
                  'content': {
                    // Not of type text, image, audio, or resource.
                    'type': 'unknown',
                    'text': 'Hi there!',
                    'data': 'Hi there!',
                  },
                },
              ],
              'maxTokens': 512,
            },
          );
          expect(extractResponse(response), ['TOKENS: 512', 'UNKNOWN']);
        });

        test('throws for invalid requests', () async {
          final dtdClient = testHarness.fakeEditorExtension!.dtd;
          final samplingServiceName = await getSamplingServiceName(dtdClient);
          try {
            await dtdClient.call(
              samplingServiceName,
              McpServiceConstants.samplingRequest,
              params: {
                'messages': [
                  {
                    'role': 'dog', // Invalid role.
                    'content': {
                      'type': 'text',
                      'text': 'Hi! I have a question.',
                    },
                  },
                ],
                'maxTokens': 512,
              },
            );
            fail('Expected an RpcException to be thrown.');
          } catch (e) {
            expect(e, isA<RpcException>());
          }
        });
      });

      group('dart cli tests', () {
        test('can perform a hot reload', () async {
          final exampleApp = await Directory.systemTemp.createTemp('dart_app');
          addTearDown(() async {
            await _deleteWithRetry(exampleApp);
          });
          final mainFile = File.fromUri(
            exampleApp.uri.resolve('bin/main.dart'),
          );
          await mainFile.create(recursive: true);
          await mainFile.writeAsString(exampleMain);

          final debugSession = await testHarness.startDebugSession(
            exampleApp.path,
            'bin/main.dart',
            isFlutter: false,
          );

          final stdout = debugSession.appProcess.stdout;
          final stdin = debugSession.appProcess.stdin;
          await stdout.skip(1); // VM service line
          stdin.writeln('');
          expect(await stdout.next, 'hello');
          await Future<void>.delayed(const Duration(seconds: 1));

          final originalContents = await mainFile.readAsString();
          expect(originalContents, contains('hello'));
          await mainFile.writeAsString(
            originalContents.replaceFirst('hello', 'world'),
          );

          final tools =
              (await testHarness.mcpServerConnection.listTools()).tools;
          final hotReloadTool = tools.singleWhere(
            (t) => t.name == DartToolingDaemonSupport.hotReloadTool.name,
          );
          final hotReloadResult = await testHarness.callToolWithRetry(
            CallToolRequest(name: hotReloadTool.name),
          );
          expect(hotReloadResult.isError, isNot(true));
          expect(
            (hotReloadResult.content.single as TextContent).text,
            startsWith('Hot reload succeeded'),
          );

          stdin.writeln('');
          expect(await stdout.next, 'world');

          stdin.writeln('q');
          await testHarness.stopDebugSession(debugSession);
        });
      });
    });

    group('[in process]', () {
      late ua.FakeAnalytics analytics;
      late DartMCPServer server;
      setUp(() async {
        DartToolingDaemonSupport.debugAwaitVmServiceDisposal = true;
        addTearDown(
          () => DartToolingDaemonSupport.debugAwaitVmServiceDisposal = false,
        );

        testHarness = await TestHarness.start(inProcess: true);
        server = testHarness.serverConnectionPair.server!;
        analytics = server.analytics! as ua.FakeAnalytics;
        await testHarness.connectToDtd();
      });

      group('generateClientId creates ID from client name', () {
        test('removes whitespaces', () {
          // Single whitespace character.
          expect(
            server.generateClientId('Example Name'),
            startsWith('example_name_'),
          );
          // Multiple whitespace characters.
          expect(
            server.generateClientId('Example   Name'),
            startsWith('example_name_'),
          );
          // Newline and other whitespace.
          expect(
            server.generateClientId('Example\n\tName'),
            startsWith('example_name_'),
          );
          // Whitespace at the end.
          expect(
            server.generateClientId('Example Name\n'),
            startsWith('example_name_'),
          );
        });

        test('replaces periods and dashes with underscores', () {
          // Replaces periods.
          expect(
            server.generateClientId('Example.Client.Name'),
            startsWith('example_client_name_'),
          );
          // Replaces dashes.
          expect(
            server.generateClientId('example-client-name'),
            startsWith('example_client_name_'),
          );
        });

        test('removes special characters', () {
          expect(
            server.generateClientId('Example!@#Client\$%^Name'),
            startsWith('exampleclientname_'),
          );
        });

        test('handles a mix of sanitization rules', () {
          expect(
            server.generateClientId('  Example Client.Name!@# '),
            startsWith('example_client_name_'),
          );
        });

        test('ends with an 8-character uuid', () {
          expect(
            server.generateClientId('Example name'),
            matches(RegExp(r'[a-f0-9]{8}$')),
          );
        });
      });

      group('$VmService management', () {
        late Directory appDir;
        final appPath = 'bin/main.dart';

        setUp(() async {
          appDir = await Directory.systemTemp.createTemp('dart_app');
          addTearDown(() async {
            await _deleteWithRetry(appDir);
          });
          final mainFile = File.fromUri(appDir.uri.resolve(appPath));
          await mainFile.create(recursive: true);
          await mainFile.writeAsString(exampleMain);
        });

        test('persists vm services', () async {
          final server = testHarness.serverConnectionPair.server!;
          expect(server.activeVmServices, isEmpty);

          await testHarness.startDebugSession(
            appDir.path,
            appPath,
            isFlutter: false,
          );
          await server.updateActiveVmServices();
          expect(server.activeVmServices.length, 1);

          // Re-uses existing VM Service when available.
          final originalVmService = server.activeVmServices.values.single;
          await server.updateActiveVmServices();
          expect(server.activeVmServices.length, 1);
          expect(originalVmService, server.activeVmServices.values.single);

          await testHarness.startDebugSession(
            appDir.path,
            appPath,
            isFlutter: false,
          );
          await server.updateActiveVmServices();
          expect(server.activeVmServices.length, 2);
        });

        test('automatically removes vm services upon shutdown', () async {
          final server = testHarness.serverConnectionPair.server!;
          expect(server.activeVmServices, isEmpty);

          final debugSession = await testHarness.startDebugSession(
            appDir.path,
            appPath,
            isFlutter: false,
          );
          await pumpEventQueue();
          await runWithRetry(
            callback: () => expect(server.activeVmServices.length, 1),
            maxRetries: 5,
          );

          // TODO: It can cause an error in the mcp server if we haven't set
          // up the listeners yet.
          await Future<void>.delayed(const Duration(seconds: 1));

          await testHarness.stopDebugSession(debugSession);
          await pumpEventQueue();
          expect(server.activeVmServices, isEmpty);
        });
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

      test('can take a screenshot using flutter_driver', () async {
        await testHarness.startDebugSession(
          counterAppPath,
          'lib/driver_main.dart',
          isFlutter: true,
        );
        final screenshotResult = await testHarness.callToolWithRetry(
          CallToolRequest(
            name: DartToolingDaemonSupport.flutterDriverTool.name,
            arguments: {'command': 'screenshot'},
          ),
        );
        expect(screenshotResult.content.single, {
          'data': anything,
          'mimeType': 'image/png',
          'type': ImageContent.expectedType,
        });
      });

      group('get selected widget', () {
        test('when a selected widget exists', () async {
          final server = testHarness.serverConnectionPair.server!;

          await testHarness.startDebugSession(
            counterAppPath,
            'lib/main.dart',
            isFlutter: true,
          );
          await server.updateActiveVmServices();

          final getWidgetTreeResult = await testHarness.callToolWithRetry(
            CallToolRequest(
              name: DartToolingDaemonSupport.getWidgetTreeTool.name,
              arguments: {'summaryOnly': true},
            ),
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
          final getSelectedWidgetResult = await testHarness.callTool(
            CallToolRequest(
              name: DartToolingDaemonSupport.getSelectedWidgetTool.name,
            ),
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
          final getSelectedWidgetResult = await testHarness.callToolWithRetry(
            CallToolRequest(
              name: DartToolingDaemonSupport.getSelectedWidgetTool.name,
            ),
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

        late Directory appDir;
        final appPath = 'bin/main.dart';
        late AppDebugSession debugSession;

        setUp(() async {
          appDir = await Directory.systemTemp.createTemp('dart_app');
          addTearDown(() async {
            await _deleteWithRetry(appDir);
          });
          final mainFile = File.fromUri(appDir.uri.resolve(appPath));
          await mainFile.create(recursive: true);
          await mainFile.writeAsString(
            exampleMain.replaceFirst(
              "print('hello')",
              "stderr.writeln('error!');",
            ),
          );

          debugSession = await testHarness.startDebugSession(
            appDir.path,
            appPath,
            isFlutter: false,
          );
        });

        test('can be read and cleared using the tool', () async {
          final tools =
              (await testHarness.mcpServerConnection.listTools()).tools;
          final runtimeErrorsTool = tools.singleWhere(
            (t) => t.name == DartToolingDaemonSupport.getRuntimeErrorsTool.name,
          );

          final stdin = debugSession.appProcess.stdin;

          /// Waits up to a second for errors to appear, returns first result
          /// that does have some errors.
          Future<CallToolResult> expectErrors({
            required bool clearErrors,
          }) async {
            late CallToolResult runtimeErrorsResult;
            var count = 0;
            while (true) {
              runtimeErrorsResult = await testHarness.callToolWithRetry(
                CallToolRequest(
                  name: runtimeErrorsTool.name,
                  arguments: {'clearRuntimeErrors': clearErrors},
                ),
              );
              expect(runtimeErrorsResult.isError, isNot(true));
              final firstText =
                  (runtimeErrorsResult.content.first as TextContent).text;
              if (errorCountRegex.hasMatch(firstText)) {
                return runtimeErrorsResult;
              } else if (++count > 10) {
                fail('No errors found, expected at least one');
              } else {
                await Future<void>.delayed(const Duration(milliseconds: 100));
              }
            }
          }

          // Give the errors at most a second to come through.
          stdin.writeln('');
          final runtimeErrorsResult = await expectErrors(clearErrors: true);
          expect(
            (runtimeErrorsResult.content.first as TextContent).text,
            contains(errorCountRegex),
          );
          expect(
            (runtimeErrorsResult.content[1] as TextContent).text,
            contains('error!'),
          );

          // We cleared the errors in the previous call, shouldn't see any here.
          final nextResult = await testHarness.callToolWithRetry(
            CallToolRequest(name: runtimeErrorsTool.name),
          );
          expect(
            (nextResult.content.first as TextContent).text,
            contains('No runtime errors found'),
          );

          // Trigger another error.
          stdin.writeln('');
          final finalRuntimeErrorsResult = await expectErrors(
            clearErrors: false,
          );
          expect(
            (finalRuntimeErrorsResult.content.first as TextContent).text,
            contains(errorCountRegex),
          );
          expect(
            (finalRuntimeErrorsResult.content[1] as TextContent).text,
            contains('error!'),
          );
        });

        test(
          'can be read and subscribed to as a resource',
          () async {
            final serverConnection = testHarness.mcpServerConnection;
            final onResourceListChanged =
                serverConnection.resourceListChanged.first;

            final stdin = debugSession.appProcess.stdin;
            stdin.writeln('');
            var resources = (await serverConnection.listResources(
              ListResourcesRequest(),
            )).resources;
            if (resources.runtimeErrors.isEmpty) {
              await onResourceListChanged;
              resources = (await serverConnection.listResources(
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
            var originalContents = (await serverConnection.readResource(
              ReadResourceRequest(uri: resource.uri),
            )).contents;
            final errorMatcher = isA<TextResourceContents>().having(
              (c) => c.text,
              'text',
              contains('error!'),
            );
            // If we haven't seen errors initially, then listen for updates and
            // re-read the resource.
            if (originalContents.isEmpty) {
              await resourceUpdatedQueue.next;
              originalContents = (await serverConnection.readResource(
                ReadResourceRequest(uri: resource.uri),
              )).contents;
            }
            expect(
              originalContents.length,
              1,
              reason: 'should have exactly one error, got $originalContents',
            );
            expect(originalContents.single, errorMatcher);

            stdin.writeln('');
            expect(
              await resourceUpdatedQueue.next,
              isA<ResourceUpdatedNotification>().having(
                (n) => n.uri,
                ParameterNames.uri,
                resource.uri,
              ),
            );

            // Should now have another error.
            final newContents = (await serverConnection.readResource(
              ReadResourceRequest(uri: resource.uri),
            )).contents;
            expect(newContents.length, 2);
            expect(newContents.last, errorMatcher);

            // Clear previous errors.
            await testHarness.callToolWithRetry(
              CallToolRequest(
                name: DartToolingDaemonSupport.getRuntimeErrorsTool.name,
                arguments: {'clearRuntimeErrors': true},
              ),
            );

            final finalContents = (await serverConnection.readResource(
              ReadResourceRequest(uri: resource.uri),
            )).contents;
            expect(finalContents, isEmpty);

            expect(
              analytics.sentEvents,
              contains(
                isA<ua.Event>()
                    .having(
                      (e) => e.eventName,
                      'eventName',
                      DashEvent.dartMCPEvent,
                    )
                    .having(
                      (e) => e.eventData,
                      'eventData',
                      equals({
                        'client': server.clientInfo.name,
                        'clientVersion': server.clientInfo.version,
                        'serverVersion': server.implementation.version,
                        'type': 'readResource',
                        'kind': ResourceKind.runtimeErrors.name,
                        'length': isA<int>(),
                        'elapsedMilliseconds': isA<int>(),
                      }),
                    ),
              ),
            );
          },
          onPlatform: {
            'windows': const Skip('https://github.com/dart-lang/ai/issues/151'),
          },
        );
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
          await fakeEditor!.dtd.postEvent(
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

      test('can enable and disable widget selection mode', () async {
        final debugSession = await testHarness.startDebugSession(
          counterAppPath,
          'lib/main.dart',
          isFlutter: true,
        );
        final tools = (await testHarness.mcpServerConnection.listTools()).tools;
        final setSelectionModeTool = tools.singleWhere(
          (t) =>
              t.name ==
              DartToolingDaemonSupport.setWidgetSelectionModeTool.name,
        );

        // Enable selection mode
        final enableResult = await testHarness.callToolWithRetry(
          CallToolRequest(
            name: setSelectionModeTool.name,
            arguments: {'enabled': true},
          ),
        );

        expect(enableResult.isError, isNot(true));
        expect(enableResult.content, [
          TextContent(text: 'Widget selection mode enabled.'),
        ]);

        // Disable selection mode
        final disableResult = await testHarness.callToolWithRetry(
          CallToolRequest(
            name: setSelectionModeTool.name,
            arguments: {'enabled': false},
          ),
        );

        expect(disableResult.isError, isNot(true));
        expect(disableResult.content, [
          TextContent(text: 'Widget selection mode disabled.'),
        ]);

        // Test missing 'enabled' argument
        final missingArgResult = await testHarness.callTool(
          CallToolRequest(name: setSelectionModeTool.name),
          expectError: true,
        );
        expect(missingArgResult.isError, isTrue);
        expect(
          (missingArgResult.content.first as TextContent).text,
          'Required property "enabled" is missing at path #root',
        );

        // Clean up
        await testHarness.stopDebugSession(debugSession);
      });

      group('Flutter driver', () {
        test('can get text and tap buttons', () async {
          final debugSession = await testHarness.startDebugSession(
            counterAppPath,
            'lib/driver_main.dart',
            isFlutter: true,
          );
          var result = await testHarness.callToolWithRetry(
            CallToolRequest(
              name: DartToolingDaemonSupport.flutterDriverTool.name,
              arguments: {
                'command': 'get_text',
                'finderType': 'ByValueKey',
                'keyValueString': 'counter',
                'keyValueType': 'String',
              },
            ),
          );
          expect(
            result.content.first,
            isA<TextContent>().having(
              (c) => c.text,
              'text',
              contains('"text":"0"'),
            ),
          );

          result = await testHarness.callToolWithRetry(
            CallToolRequest(
              name: DartToolingDaemonSupport.flutterDriverTool.name,
              arguments: {
                'command': 'tap',
                'finderType': 'ByTooltipMessage',
                'text': 'Increment',
              },
            ),
          );
          expect(result.isError, isNot(true));

          result = await testHarness.callToolWithRetry(
            CallToolRequest(
              name: DartToolingDaemonSupport.flutterDriverTool.name,
              arguments: {
                'command': 'get_text',
                'finderType': 'ByValueKey',
                'keyValueString': 'counter',
                'keyValueType': 'String',
              },
            ),
          );
          expect(
            result.content.first,
            isA<TextContent>().having(
              (c) => c.text,
              'text',
              contains('"text":"1"'),
            ),
          );

          // Clean up
          await testHarness.stopDebugSession(debugSession);
        });
      });
    });

    test('Does not include flutter tools with --tools=dart', () async {
      testHarness = await TestHarness.start(
        inProcess: false,
        cliArgs: ['--tools', 'dart'],
      );
      final connection = testHarness.serverConnectionPair.serverConnection;

      final tools = (await connection.listTools()).tools;
      final unexpectedTools = [
        'take_screenshot',
        'get_widget_tree',
        'get_selected_widget',
        'set_widget_selection_mode',
        'flutter_driver',
      ];
      for (final name in unexpectedTools) {
        expect(
          tools,
          isNot(contains(predicate<Tool>((tool) => tool.name == name))),
        );
      }
      expect(tools, isNotEmpty);
    });
  });

  group('ErrorLog', () {
    test('adds errors and respects max size', () {
      final log = ErrorLog(maxSize: 10);
      log.add('abc');
      expect(log.errors, ['abc']);
      expect(log.characters, 3);

      log.add('defg');
      expect(log.errors, ['abc', 'defg']);
      expect(log.characters, 7);

      log.add('hijkl');
      expect(log.errors, ['defg', 'hijkl']);
      expect(log.characters, 9);

      log.add('mnopq');
      expect(log.errors, ['hijkl', 'mnopq']);
      expect(log.characters, 10);
    });

    test('handles single error larger than max size', () {
      final log = ErrorLog(maxSize: 10);
      log.add('abcdefghijkl');
      expect(log.errors, ['abcdefghij']);
      expect(log.characters, 10);

      log.add('mnopqrstuvwxyz');
      expect(log.errors, ['mnopqrstuv']);
      expect(log.characters, 10);
    });

    test('clear removes all errors', () {
      final log = ErrorLog(maxSize: 10);
      log
        ..add('abc')
        ..add('def');
      log.clear();
      expect(log.errors, isEmpty);
      expect(log.characters, 0);
    });

    test('add, clear,clear and then add again', () {
      final log = ErrorLog(maxSize: 10);
      log
        ..add('abc')
        ..add('def');
      log.clear();
      expect(log.errors, isEmpty);
      expect(log.characters, 0);
      log.add('ghi');
      expect(log.errors, ['ghi']);
      expect(log.characters, 3);
      log.add('jklmnopqrstuv');
      expect(log.errors, ['jklmnopqrs']);
      expect(log.characters, 10);
    });
  });

  test('connect_to_dtd will reject a vm service URI', () async {
    final testHarness = await TestHarness.start(inProcess: true);
    final debugSession = await testHarness.startDebugSession(
      dartCliAppsPath,
      'bin/infinite_wait.dart',
      isFlutter: false,
    );
    final connectResult = await testHarness.connectToDtd(
      dtdUri: debugSession.vmServiceUri,
      expectError: true,
    );
    expect(
      (connectResult.content.first as TextContent).text,
      contains('Connected to a VM Service'),
    );
    final retryResult = await testHarness.connectToDtd();
    expect(retryResult.isError, isNot(true));
  });
}

extension on Iterable<Resource> {
  Iterable<Resource> get runtimeErrors => where(
    (r) => r.uri.startsWith(DartToolingDaemonSupport.runtimeErrorsScheme),
  );
}

/// A dart app which exits when it receives a `q` on stdin, and prints 'hello'
/// on any other input.
final exampleMain = '''
import 'dart:convert';
import 'dart:io';

void main() async {
  stdin.listen((bytes) {
    if (utf8.decode(bytes).contains('q')) exit(0);
    action();
  });
}

void action() {
  print('hello');
}
''';

/// Tries to delete [dir] up to 5 times, waiting 200ms between each.
///
/// Necessary for windows tests.
Future<void> _deleteWithRetry(Directory dir) async {
  var i = 0;
  while (++i <= 5) {
    try {
      await dir.delete(recursive: true);
      return;
    } catch (_) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }
}
