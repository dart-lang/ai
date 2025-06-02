// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:async/async.dart';
import 'package:dart_mcp/server.dart';
import 'package:dart_mcp_server/src/mixins/dtd.dart';
import 'package:dart_mcp_server/src/utils/constants.dart';
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

      group('flutter tests', () {
        test('can take a screenshot', () async {
          await testHarness.startDebugSession(
            counterAppPath,
            'lib/main.dart',
            isFlutter: true,
          );
          final tools =
              (await testHarness.mcpServerConnection.listTools()).tools;
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
      setUp(() async {
        DartToolingDaemonSupport.debugAwaitVmServiceDisposal = true;
        addTearDown(
          () => DartToolingDaemonSupport.debugAwaitVmServiceDisposal = false,
        );

        testHarness = await TestHarness.start(inProcess: true);
        await testHarness.connectToDtd();
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
            var originalContents =
                (await serverConnection.readResource(
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
              originalContents =
                  (await serverConnection.readResource(
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
            final newContents =
                (await serverConnection.readResource(
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

            final finalContents =
                (await serverConnection.readResource(
                  ReadResourceRequest(uri: resource.uri),
                )).contents;
            expect(finalContents, isEmpty);
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
        final missingArgResult = await testHarness.callToolWithRetry(
          CallToolRequest(name: setSelectionModeTool.name),
          expectError: true,
        );
        expect(missingArgResult.isError, isTrue);
        expect(
          (missingArgResult.content.first as TextContent).text,
          'Required parameter "enabled" was not provided or is not a boolean.',
        );

        // Clean up
        await testHarness.stopDebugSession(debugSession);
      });
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
