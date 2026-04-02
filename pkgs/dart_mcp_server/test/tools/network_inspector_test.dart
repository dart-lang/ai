// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:dart_mcp/server.dart';
import 'package:dart_mcp_server/src/features_configuration.dart';
import 'package:dart_mcp_server/src/mixins/dtd.dart';
import 'package:dart_mcp_server/src/utils/names.dart';
import 'package:process/process.dart';
import 'package:test/test.dart';

import '../test_harness.dart';

void main() {
  late TestHarness testHarness;

  group('network inspector tools', () {
    group('[in-process]', () {
      setUp(() async {
        testHarness = await TestHarness.start(
          featuresConfig: FeaturesConfiguration(
            enabledNames: {FeatureCategory.networkInspector.name},
          ),
          inProcess: true,
        );
        await testHarness.connectToDtd();
      });

      test('network inspector tools are registered', () async {
        final tools =
            (await testHarness.mcpServerConnection.listTools()).tools;
        final toolNames = tools.map((t) => t.name).toSet();

        expect(toolNames, contains(ToolNames.getNetworkLogs.name));
        expect(toolNames, contains(ToolNames.clearNetworkLogs.name));
        expect(toolNames, contains(ToolNames.getNetworkRequest.name));
      });

      test('get_network_logs returns error when DTD not connected', () async {
        // Create a fresh harness without connecting to DTD.
        final freshHarness = await TestHarness.start(
          featuresConfig: FeaturesConfiguration(
            enabledNames: {FeatureCategory.networkInspector.name},
          ),
          inProcess: true,
        );

        final result = await freshHarness.mcpServerConnection.callTool(
          CallToolRequest(
            name: ToolNames.getNetworkLogs.name,
            arguments: {},
          ),
        );

        expect(result.isError, true);
      });
    });

    group('[compiled server]', () {
      setUp(() async {
        testHarness = await TestHarness.start(
          featuresConfig: FeaturesConfiguration(
            enabledNames: {FeatureCategory.networkInspector.name},
          ),
          inProcess: false,
          processManager: const LocalProcessManager(),
        );
        await testHarness.connectToDtd();
      });

      group('flutter app tests', () {
        test('get_network_logs returns empty list when no requests made',
            () async {
          await testHarness.startDebugSession(
            counterAppPath,
            'lib/main.dart',
            isFlutter: true,
          );

          final result = await testHarness.callToolWithRetry(
            CallToolRequest(
              name: ToolNames.getNetworkLogs.name,
              arguments: {},
            ),
          );

          expect(result.isError, isNot(true));
          final text = (result.content.first as TextContent).text;
          final decoded = jsonDecode(text) as List;
          expect(decoded, isEmpty);
        });

        test('clear_network_logs succeeds', () async {
          await testHarness.startDebugSession(
            counterAppPath,
            'lib/main.dart',
            isFlutter: true,
          );

          final result = await testHarness.callToolWithRetry(
            CallToolRequest(
              name: ToolNames.clearNetworkLogs.name,
              arguments: {},
            ),
          );

          expect(result.isError, isNot(true));
        });
      });
    });
  });
}
