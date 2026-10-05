// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:dart_mcp_server/src/features_configuration.dart';
import 'package:dart_mcp_server/src/server.dart';
import 'package:dart_mcp_server/src/utils/analytics.dart';
import 'package:dart_mcp_server/src/utils/names.dart';
import 'package:json_rpc_2/json_rpc_2.dart' show RpcException;
import 'package:test/test.dart';
import 'package:unified_analytics/testing.dart';
import 'package:unified_analytics/unified_analytics.dart';

import '../test_harness.dart';

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

    test('sends an initialize event', () {
      expect(
        analytics.sentEvents.first,
        isA<Event>()
            .having((e) => e.eventName, 'eventName', DashEvent.dartMCPEvent)
            .having(
              (e) => e.eventData,
              'eventData',
              equals({
                'client': server.clientInfo.name,
                'clientVersion': server.clientInfo.version,
                'serverVersion': server.implementation.version,
                'type': AnalyticsEvent.initialize.name,
                'supportsElicitation': true,
                'supportsRoots': true,
                'supportsSampling': true,
              }),
            ),
      );
    });

    test('are sent for listTools', () async {
      await server.listTools();

      expect(
        analytics.sentEvents.last,
        isA<Event>()
            .having((e) => e.eventName, 'eventName', DashEvent.dartMCPEvent)
            .having(
              (e) => e.eventData,
              'eventData',
              equals({
                'client': server.clientInfo.name,
                'clientVersion': server.clientInfo.version,
                'serverVersion': server.implementation.version,
                'type': AnalyticsEvent.listTools.name,
              }),
            ),
      );
    });

    test('are sent for listPrompts', () async {
      await server.listPrompts();

      expect(
        analytics.sentEvents.last,
        isA<Event>()
            .having((e) => e.eventName, 'eventName', DashEvent.dartMCPEvent)
            .having(
              (e) => e.eventData,
              'eventData',
              equals({
                'client': server.clientInfo.name,
                'clientVersion': server.clientInfo.version,
                'serverVersion': server.implementation.version,
                'type': AnalyticsEvent.listPrompts.name,
              }),
            ),
      );
    });

    test('are sent for listResources', () async {
      await server.listResources();

      expect(
        analytics.sentEvents.last,
        isA<Event>()
            .having((e) => e.eventName, 'eventName', DashEvent.dartMCPEvent)
            .having(
              (e) => e.eventData,
              'eventData',
              equals({
                'client': server.clientInfo.name,
                'clientVersion': server.clientInfo.version,
                'serverVersion': server.implementation.version,
                'type': AnalyticsEvent.listResources.name,
              }),
            ),
      );
    });

    test('are sent for listResourceTemplates', () async {
      await server.listResourceTemplates();

      expect(
        analytics.sentEvents.last,
        isA<Event>()
            .having((e) => e.eventName, 'eventName', DashEvent.dartMCPEvent)
            .having(
              (e) => e.eventData,
              'eventData',
              equals({
                'client': server.clientInfo.name,
                'clientVersion': server.clientInfo.version,
                'serverVersion': server.implementation.version,
                'type': AnalyticsEvent.listResourceTemplates.name,
              }),
            ),
      );
    });

    test('are sent for successful tool calls', () async {
      server.registerTool(
        Tool(name: 'hello', inputSchema: Schema.object())
          ..categories = [FeatureCategory.cli],
        (_) => CallToolResult(content: [Content.text(text: 'world')]),
      );
      final result = await testHarness.callToolWithRetry(
        CallToolRequest(name: 'hello'),
      );
      expect((result.content.single as TextContent).text, 'world');
      expect(
        analytics.sentEvents.last,
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

    test('are sent for failed tool calls', () async {
      analytics.sentEvents.clear();

      final tool = Tool(name: 'hello', inputSchema: Schema.object())
        ..categories = [FeatureCategory.cli];
      server.registerTool(
        tool,
        (_) => CallToolResult(isError: true, content: [])..failureReason = null,
      );
      final result = await testHarness.mcpServerConnection.callTool(
        CallToolRequest(name: tool.name),
      );
      expect(result.isError, true);
      expect(
        analytics.sentEvents.last,
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

    test('are sent for tool calls with argument errors', () async {
      analytics.sentEvents.clear();

      final tool = Tool(
        name: 'hello',
        inputSchema: Schema.object(
          properties: {'name': Schema.string()},
          required: ['name'],
        ),
      )..categories = [FeatureCategory.cli];
      server.registerTool(
        tool,
        (_) => CallToolResult(content: [Content.text(text: 'world')]),
      );
      final result = await testHarness.mcpServerConnection.callTool(
        CallToolRequest(name: tool.name),
      );
      expect(result.isError, true);
      expect(
        analytics.sentEvents.last,
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
                'failureReason': 'argumentError',
                'elapsedMilliseconds': isA<int>(),
              }),
            ),
      );
    });

    test('are sent for tool calls that throw errors', () async {
      analytics.sentEvents.clear();

      final tool = Tool(name: 'hello', inputSchema: Schema.object())
        ..categories = [FeatureCategory.cli];
      server.registerTool(tool, (_) => throw StateError('uh oh!'));
      final result = await testHarness.mcpServerConnection.callTool(
        CallToolRequest(name: tool.name),
      );
      expect(result.isError, true);
      expect(
        analytics.sentEvents.last,
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
                'failureReason': 'unhandledError',
                'errorType': 'StateError',
                'elapsedMilliseconds': isA<int>(),
              }),
            ),
      );
    });

    test('includes known commands in the tool name', () async {
      analytics.sentEvents.clear();
      final tool = Tool(
        name: 'meta_tool',
        inputSchema: Schema.object(
          properties: {
            ParameterNames.command: EnumSchema.untitledSingleSelect(
              values: ['hello'],
            ),
          },
          required: [ParameterNames.command],
        ),
      )..categories = [FeatureCategory.cli];
      server.registerTool(
        tool,
        (request) => CallToolResult(
          content: [
            Content.text(
              text: request.arguments![ParameterNames.command] as String,
            ),
          ],
        ),
      );
      await testHarness.mcpServerConnection.callTool(
        CallToolRequest(
          name: tool.name,
          arguments: {ParameterNames.command: 'hello'},
        ),
      );
      expect(
        analytics.sentEvents.last,
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
                'tool': '${tool.name}.hello',
                'success': true,
                'elapsedMilliseconds': isA<int>(),
              }),
            ),
      );
    });

    test('does not include unknown commands in the tool name', () async {
      analytics.sentEvents.clear();
      final tool = Tool(
        name: 'meta_tool',
        inputSchema: Schema.object(
          properties: {
            ParameterNames.command: EnumSchema.untitledSingleSelect(
              values: ['hello'],
            ),
          },
          required: [ParameterNames.command],
        ),
      )..categories = [FeatureCategory.cli];
      server.registerTool(tool, (_) => CallToolResult(content: []));
      final result = await testHarness.mcpServerConnection.callTool(
        CallToolRequest(
          name: tool.name,
          arguments: {ParameterNames.command: r'hello ${oops}'},
        ),
      );
      expect(result.isError, true);
      expect(
        analytics.sentEvents.last,
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
                'failureReason': CallToolFailureReason.noSuchCommand.name,
                'elapsedMilliseconds': isA<int>(),
              }),
            ),
      );
    });

    test(
      'does not include commands for tools without known commands',
      () async {
        analytics.sentEvents.clear();
        final toolWithoutCommands = Tool(
          name: 'no_commands',
          inputSchema: Schema.object(),
        )..categories = [FeatureCategory.cli];
        final toolWithFreeFormCommands = Tool(
          name: 'free_form_commands',
          inputSchema: Schema.object(
            properties: {ParameterNames.command: Schema.string()},
          ),
        )..categories = [FeatureCategory.cli];
        for (final tool in [toolWithoutCommands, toolWithFreeFormCommands]) {
          server.registerTool(tool, (_) => CallToolResult(content: []));
          await testHarness.mcpServerConnection.callTool(
            CallToolRequest(
              name: tool.name,
              arguments: {ParameterNames.command: r'${oops}'},
            ),
          );
          expect(
            analytics.sentEvents.last,
            isA<Event>().having((e) => e.eventData['tool'], 'tool', tool.name),
          );
        }
      },
    );

    test('are not sent for unknown tools', () async {
      analytics.sentEvents.clear();
      final result = await testHarness.mcpServerConnection.callTool(
        CallToolRequest(name: r'not_a_real_tool_${oops}'),
      );
      expect(result.isError, true);
      expect(
        analytics.sentEvents,
        isEmpty,
        reason:
            'Tool names come directly from the client, so we should never log '
            'ones that we do not recognize.',
      );
    });

    test('can include the commands for all registered tools', () async {
      final toolsWithCommands = [
        for (final tool in (await server.listTools()).tools)
          if (tool.inputSchema.properties?[ParameterNames.command]
              case final commandSchema?)
            (tool.name, commandSchema as StringSchema),
      ];
      // Make sure we are actually testing something.
      expect(toolsWithCommands, isNotEmpty);
      for (final (toolName, commandSchema) in toolsWithCommands) {
        expect(
          commandSchema.enumValues ?? const <String>[],
          isNotEmpty,
          reason:
              'The `${ParameterNames.command}` parameter of the `$toolName` '
              'tool must list its allowed values in an `enum`, because only '
              'those values are included in analytics.',
        );
      }
    });

    test('can include the names of all registered prompts', () async {
      final promptNames = [
        for (final prompt in (await server.listPrompts()).prompts) prompt.name,
      ];
      // Make sure we are actually testing something.
      expect(promptNames, isNotEmpty);
      expect(
        promptNames,
        everyElement(isIn(PromptNames.values.map((p) => p.name))),
        reason:
            'All prompts must be listed in `PromptNames`, because only those '
            'prompt names are included in analytics.',
      );
    });

    test('includes custom metrics if provided', () async {
      analytics.sentEvents.clear();
      final tool = Tool(name: 'hello', inputSchema: Schema.object())
        ..categories = [FeatureCategory.cli];
      server.registerTool(
        tool,
        (_) =>
            CallToolResult(content: [Content.text(text: 'world')])
              ..customMetrics = FakeCustomMetrics('world'),
      );
      await testHarness.mcpServerConnection.callTool(
        CallToolRequest(name: tool.name),
      );
      expect(
        analytics.sentEvents.last,
        isA<Event>()
            .having((e) => e.eventName, 'eventName', DashEvent.dartMCPEvent)
            .having(
              (e) => e.eventData['customValue'],
              'eventData.customValue',
              equals('world'),
            ),
      );
    });

    group('are sent for prompts', () {
      // We only log the names of the prompts that are set up by this server,
      // so this fake prompt replaces one of those.
      final helloPrompt = Prompt(
        name: PromptNames.flutterDriverUserJourneyTest.name,
        arguments: [PromptArgument(name: 'name', required: false)],
      )..categories = [FeatureCategory.cli];
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
        server
          ..removePrompt(helloPrompt.name)
          ..addPrompt(helloPrompt, getHelloPrompt);
      });

      test('with no arguments', () async {
        final result = await testHarness.getPrompt(
          GetPromptRequest(name: helloPrompt.name),
        );
        expect((result.messages.single.content as TextContent).text, 'hello');
        expect(result.messages.single.role, Role.user);
        expect(
          analytics.sentEvents.last,
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
          analytics.sentEvents.last,
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
          analytics.sentEvents.last,
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

      test('without the name if it is unknown', () async {
        analytics.sentEvents.clear();
        await expectLater(
          testHarness.getPrompt(
            GetPromptRequest(name: r'not_a_real_prompt_${oops}'),
          ),
          throwsA(isA<RpcException>()),
        );
        expect(
          analytics.sentEvents.last,
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
                  'success': false,
                  'failureReason': GetPromptFailureReason.noSuchPrompt.name,
                  'elapsedMilliseconds': isA<int>(),
                  'withArguments': false,
                }),
              ),
        );
      });
    });

    test('includes agentPlugin in sent events when provided', () async {
      await withAgentPluginOverride('dart-flutter', () async {
        await server.listTools();

        expect(
          analytics.sentEvents.last,
          isA<Event>()
              .having((e) => e.eventName, 'eventName', DashEvent.dartMCPEvent)
              .having(
                (e) => e.eventData,
                'eventData',
                containsPair('agentPlugin', 'dart-flutter'),
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
}

final class FakeCustomMetrics extends CustomMetrics {
  final String customValue;
  FakeCustomMetrics(this.customValue);

  @override
  Map<String, Object> toMap() => {'customValue': customValue};
}
