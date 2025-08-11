// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:dart_mcp_server/src/arg_parser.dart';
import 'package:dart_mcp_server/src/mixins/analyzer.dart';
import 'package:dart_mcp_server/src/mixins/dtd.dart';
import 'package:dart_mcp_server/src/server.dart';
import 'package:dart_mcp_server/src/utils/analytics.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;
import 'package:unified_analytics/testing.dart';
import 'package:unified_analytics/unified_analytics.dart';

import 'test_harness.dart';

void main() {
  group('analytics', () {
    late TestHarness testHarness;
    late DartMCPServer server;
    late FakeAnalytics analytics;

    setUp(() async {
      testHarness = await TestHarness.start(inProcess: true);
      server = testHarness.serverConnectionPair.server!;
      analytics = server.analytics as FakeAnalytics;
    });

    test('sends analytics for successful tool calls', () async {
      server.registerTool(
        Tool(name: 'hello', inputSchema: Schema.object()),
        (_) => CallToolResult(content: [Content.text(text: 'world')]),
      );
      final result = await testHarness.callToolWithRetry(
        CallToolRequest(name: 'hello'),
      );
      expect((result.content.single as TextContent).text, 'world');
      expect(
        analytics.sentEvents.single,
        isA<Event>()
            .having((e) => e.eventName, 'eventName', DashEvent.dartMCPEvent)
            .having(
              (e) => e.eventData,
              'eventData',
              equals({
                'client': server.clientInfo.name,
                'clientVersion': server.clientInfo.version,
                'serverVersion': server.implementation.version,
                'type': AnalyticsEvent.callTool.name,
                'tool': 'hello',
                'success': true,
                'elapsedMilliseconds': isA<int>(),
              }),
            ),
      );
    });

    test('sends analytics for failed tool calls', () async {
      analytics.sentEvents.clear();

      final tool = Tool(name: 'hello', inputSchema: Schema.object());
      server.registerTool(
        tool,
        (_) => CallToolResult(isError: true, content: [])..failureReason = null,
      );
      final result = await testHarness.mcpServerConnection.callTool(
        CallToolRequest(name: tool.name),
      );
      expect(result.isError, true);
      expect(
        analytics.sentEvents.single,
        isA<Event>()
            .having((e) => e.eventName, 'eventName', DashEvent.dartMCPEvent)
            .having(
              (e) => e.eventData,
              'eventData',
              equals({
                'client': server.clientInfo.name,
                'clientVersion': server.clientInfo.version,
                'serverVersion': server.implementation.version,
                'type': AnalyticsEvent.callTool.name,
                'tool': tool.name,
                'success': false,
                'elapsedMilliseconds': isA<int>(),
              }),
            ),
      );
    });

    group('are sent for prompts', () {
      final helloPrompt = Prompt(
        name: 'hello',
        arguments: [PromptArgument(name: 'name', required: false)],
      );
      GetPromptResult getHelloPrompt(GetPromptRequest request) {
        assert(request.name == helloPrompt.name);
        if (request.arguments?['throw'] == true) {
          throw StateError('Oh no!');
        }
        return GetPromptResult(
          messages: [
            PromptMessage(
              role: Role.user,
              content: Content.text(text: 'hello'),
            ),
            if (request.arguments?['name'] case final name?)
              PromptMessage(
                role: Role.user,
                content: Content.text(text: ', my name is $name'),
              ),
          ],
        );
      }

      setUp(() {
        server.addPrompt(helloPrompt, getHelloPrompt);
      });

      test('with no arguments', () async {
        final result = await testHarness.getPrompt(
          GetPromptRequest(name: helloPrompt.name),
        );
        expect((result.messages.single.content as TextContent).text, 'hello');
        expect(result.messages.single.role, Role.user);
        expect(
          analytics.sentEvents.single,
          isA<Event>()
              .having((e) => e.eventName, 'eventName', DashEvent.dartMCPEvent)
              .having(
                (e) => e.eventData,
                'eventData',
                equals({
                  'client': server.clientInfo.name,
                  'clientVersion': server.clientInfo.version,
                  'serverVersion': server.implementation.version,
                  'type': AnalyticsEvent.getPrompt.name,
                  'name': helloPrompt.name,
                  'success': true,
                  'elapsedMilliseconds': isA<int>(),
                  'withArguments': false,
                }),
              ),
        );
      });

      test('with arguments', () async {
        final result = await testHarness.getPrompt(
          GetPromptRequest(name: helloPrompt.name, arguments: {'name': 'Bob'}),
        );
        expect((result.messages[0].content as TextContent).text, 'hello');
        expect(result.messages[0].role, Role.user);
        expect(
          (result.messages[1].content as TextContent).text,
          ', my name is Bob',
        );
        expect(result.messages[1].role, Role.user);
        expect(
          analytics.sentEvents.single,
          isA<Event>()
              .having((e) => e.eventName, 'eventName', DashEvent.dartMCPEvent)
              .having(
                (e) => e.eventData,
                'eventData',
                equals({
                  'client': server.clientInfo.name,
                  'clientVersion': server.clientInfo.version,
                  'serverVersion': server.implementation.version,
                  'type': AnalyticsEvent.getPrompt.name,
                  'name': helloPrompt.name,
                  'success': true,
                  'elapsedMilliseconds': isA<int>(),
                  'withArguments': true,
                }),
              ),
        );
      });

      test('even if they throw', () async {
        try {
          await testHarness.getPrompt(
            GetPromptRequest(
              name: helloPrompt.name,
              arguments: {'throw': true},
            ),
          );
        } catch (_) {}
        expect(
          analytics.sentEvents.single,
          isA<Event>()
              .having((e) => e.eventName, 'eventName', DashEvent.dartMCPEvent)
              .having(
                (e) => e.eventData,
                'eventData',
                equals({
                  'client': server.clientInfo.name,
                  'clientVersion': server.clientInfo.version,
                  'serverVersion': server.implementation.version,
                  'type': AnalyticsEvent.getPrompt.name,
                  'name': helloPrompt.name,
                  'success': false,
                  'elapsedMilliseconds': isA<int>(),
                  'withArguments': true,
                }),
              ),
        );
      });
    });

    test('Changelog version matches dart server version', () {
      final changelogFile = File('CHANGELOG.md');
      expect(
        changelogFile.readAsLinesSync().first.split(' ')[1],
        testHarness.serverConnectionPair.server!.implementation.version,
      );
    });
  });

  group('--log-file', () {
    late d.FileDescriptor logDescriptor;
    late TestHarness testHarness;

    setUp(() async {
      logDescriptor = d.file('log.txt');
      testHarness = await TestHarness.start(
        inProcess: false,
        cliArgs: ['--log-file', logDescriptor.io.path],
      );
    });

    test('logs traffic to a file', () async {
      // It may take a bit for all the lines to show up in the log.
      await doWithRetries(
        () async => expect(
          await File(logDescriptor.io.path).readAsLines(),
          containsAll([
            allOf(startsWith('<<<'), contains('"method":"initialize"')),
            allOf(startsWith('>>>'), contains('"serverInfo"')),
            allOf(startsWith('<<<'), contains('"notifications/initialized"')),
          ]),
        ),
      );

      // Ensure the file handle is released before the file is cleaned up.
      await testHarness.serverConnectionPair.serverConnection.shutdown();

      // Wait for the process to release the file.
      await doWithRetries(() => File(logDescriptor.io.path).delete());
    });
  });

  test('Tools can be disabled with --exclude-tool', () async {
    final testHarness = await TestHarness.start(
      cliArgs: [
        '--$excludeToolOption',
        DartAnalyzerSupport.analyzeFilesTool.name,
        '--$excludeToolOption',
        DartToolingDaemonSupport.connectTool.name,
      ],
    );
    final connection = testHarness.serverConnectionPair.serverConnection;
    final tools = (await connection.listTools()).tools;
    expect(
      tools,
      isNot(contains(equals(DartAnalyzerSupport.analyzeFilesTool))),
    );
    expect(
      tools,
      isNot(contains(equals(DartToolingDaemonSupport.connectTool))),
    );
    expect(tools, contains(equals(DartAnalyzerSupport.hoverTool)));
  });
}

/// Performs [action] up to [maxRetries] times, backing off an extra 50ms
/// between each attempt.
FutureOr<T> doWithRetries<T>(
  FutureOr<T> Function() action, {
  int maxRetries = 5,
}) async {
  var count = 0;
  while (true) {
    try {
      return await action();
    } catch (_) {
      if (count == maxRetries) {
        rethrow;
      }
    }
    count++;
    await Future<void>.delayed(Duration(milliseconds: 50 * count));
  }
}
