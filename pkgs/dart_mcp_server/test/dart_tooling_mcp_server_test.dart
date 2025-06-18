// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:dart_mcp_server/src/server.dart';
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
                'type': 'callTool',
                'tool': 'hello',
                'success': true,
                'elapsedMilliseconds': isA<int>(),
              }),
            ),
      );
    });

    test('sends analytics for failed tool calls', () async {
      server.registerTool(
        Tool(name: 'hello', inputSchema: Schema.object()),
        (_) => CallToolResult(isError: true, content: []),
      );
      final result = await testHarness.mcpServerConnection.callTool(
        CallToolRequest(name: 'hello'),
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
                'type': 'callTool',
                'tool': 'hello',
                'success': false,
                'elapsedMilliseconds': isA<int>(),
              }),
            ),
      );
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
