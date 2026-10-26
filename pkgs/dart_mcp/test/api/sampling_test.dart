// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:dart_mcp/server.dart';
import 'package:dart_mcp/src/client/client.dart';
import 'package:test/test.dart';

import '../test_utils.dart';

void main() {
  group('tool content on the wire', () {
    test('ToolUseContent survives a JSON round trip', () {
      final content = ToolUseContent(
        id: 'call-1',
        name: 'lookup',
        input: {'city': 'Ankara'},
      );
      final decoded = jsonDecode(jsonEncode(content)) as Map<String, Object?>;
      final parsed = SamplingMessageContentBlock.fromMap(decoded);

      expect(parsed.isToolUse, isTrue);
      expect(parsed.isToolResult, isFalse);
      expect((parsed as ToolUseContent).input, {'city': 'Ankara'});
      expect(parsed.name, 'lookup');
    });

    test('ToolResultContent survives a JSON round trip', () {
      final content = ToolResultContent(
        content: [TextContent(text: 'sunny')],
        toolUseId: 'call-1',
        isError: false,
      );
      final decoded = jsonDecode(jsonEncode(content)) as Map<String, Object?>;
      final parsed = SamplingMessageContentBlock.fromMap(decoded);

      expect(parsed.isToolResult, isTrue);
      expect(parsed.isToolUse, isFalse);
      expect((parsed as ToolResultContent).toolUseId, 'call-1');
      expect((parsed.content.single as TextContent).text, 'sunny');
      expect(parsed.isError, isFalse);
    });

    test('a sampling message carries tool use content', () {
      final message = SamplingMessage(
        role: Role.assistant,
        content: [
          SamplingMessageContentBlock.toolUse(
            id: 'call-1',
            name: 'lookup',
            input: {},
          ),
        ],
      );
      final decoded = jsonDecode(jsonEncode(message)) as Map<String, Object?>;
      final parsed = SamplingMessage.fromMap(decoded);

      expect(parsed.content.single.isToolUse, isTrue);
      expect((parsed.content.single as ToolUseContent).id, 'call-1');
    });

    test('text content is neither tool use nor tool result', () {
      final content = SamplingMessageContentBlock.text(text: 'hi');

      expect(content.isToolUse, isFalse);
      expect(content.isToolResult, isFalse);
    });

    test('SamplingMessage round trips text content through the union', () {
      final message = SamplingMessage(
        role: Role.user,
        content: [SamplingMessageContentBlock.text(text: 'merhaba')],
      );
      final decoded = jsonDecode(jsonEncode(message)) as Map<String, Object?>;
      final parsed = SamplingMessage.fromMap(decoded);

      expect(parsed.content.single.type, TextContent.expectedType);
      expect((parsed.content.single as TextContent).text, 'merhaba');
    });

    test('SamplingMessage throws when content is missing', () {
      expect(
        () => SamplingMessage.fromMap({'role': 'user'}).content,
        throwsArgumentError,
      );
    });

    test('CreateMessageResult accepts a SamplingMessageContentBlock', () {
      final block = SamplingMessageContentBlock.toolResult(
        toolUseId: 'call-2',
        content: [TextContent(text: 'ok')],
      );
      final result = CreateMessageResult(
        role: Role.assistant,
        content: [block],
        model: 'fakeModel',
      );

      expect(result.content.single.isToolResult, isTrue);
      expect((result.content.single as ToolResultContent).toolUseId, 'call-2');
    });

    test('tools reads as null when the key is absent', () {
      final request = CreateMessageRequest(messages: [], maxTokens: 1);

      expect(request.tools, isNull);
    });
  });

  group('content as one block or a list', () {
    test('a list on the wire reads as every block in it', () {
      final message = SamplingMessage.fromMap({
        'role': 'assistant',
        'content': [
          {'type': 'text', 'text': 'first'},
          {
            'type': 'tool_use',
            'id': 'call-1',
            'name': 'lookup',
            'input': <String, Object?>{},
          },
        ],
      });

      expect(message.content, hasLength(2));
      expect((message.content.first as TextContent).text, 'first');
      expect(message.content.last.isToolUse, isTrue);
    });

    test('a bare block on the wire reads as one block', () {
      final message = SamplingMessage.fromMap({
        'role': 'user',
        'content': {'type': 'text', 'text': 'only'},
      });

      expect(message.content, hasLength(1));
      expect((message.content.single as TextContent).text, 'only');
    });

    test('one block goes on the wire as that block', () {
      final message = SamplingMessage(
        role: Role.user,
        content: [TextContent(text: 'only')],
      );
      final decoded = jsonDecode(jsonEncode(message)) as Map<String, Object?>;

      expect(decoded['content'], isA<Map<String, Object?>>());
      expect(SamplingMessage.fromMap(decoded).content, hasLength(1));
    });

    test('two blocks go on the wire as a list', () {
      final message = SamplingMessage(
        role: Role.assistant,
        content: [TextContent(text: 'first'), TextContent(text: 'second')],
      );
      final decoded = jsonDecode(jsonEncode(message)) as Map<String, Object?>;

      expect(decoded['content'], isA<List<Object?>>());
      final parsed = SamplingMessage.fromMap(decoded);
      expect(parsed.content, hasLength(2));
      expect((parsed.content.last as TextContent).text, 'second');
    });

    test('a result reads a list the same way a message does', () {
      final result = CreateMessageResult.fromMap({
        'role': 'assistant',
        'model': 'a-model',
        'content': [
          {'type': 'text', 'text': 'one'},
          {'type': 'text', 'text': 'two'},
        ],
      });

      expect(result.content, hasLength(2));
      expect((result.content.first as TextContent).text, 'one');
    });
  });

  group('CreateMessageRequest tools', () {
    test('writes and reads tools', () {
      final request = CreateMessageRequest(
        messages: [],
        maxTokens: 1,
        tools: [Tool(name: 'x', inputSchema: ObjectSchema())],
      );
      final wire = request as Map<String, Object?>;

      expect(request.tools!.single.name, 'x');
      expect(wire['tools'], hasLength(1));
    });

    test('omits tools when not provided', () {
      final wire =
          CreateMessageRequest(messages: [], maxTokens: 1)
              as Map<String, Object?>;

      expect(wire.containsKey('tools'), isFalse);
    });
  });

  test('includeContext round trips the values the schema names', () {
    for (final (value, wire) in const [
      (IncludeContext.none, 'none'),
      (IncludeContext.thisServer, 'thisServer'),
      (IncludeContext.allServers, 'allServers'),
    ]) {
      final sent =
          CreateMessageRequest(
                messages: [],
                maxTokens: 1,
                includeContext: value,
              )
              as Map<String, Object?>;
      expect(sent['includeContext'], wire);
      expect(
        CreateMessageRequest.fromMap({
          'messages': <Object?>[],
          'maxTokens': 1,
          'includeContext': wire,
        }).includeContext,
        value,
      );
    }
  });

  test('includeContext reads the name this package used to send', () {
    expect(
      CreateMessageRequest.fromMap({
        'messages': <Object?>[],
        'maxTokens': 1,
        'includeContext': 'thisService',
      }).includeContext,
      IncludeContext.thisServer,
    );
  });

  test('model preferences read an integer priority as a double', () {
    final prefs = ModelPreferences.fromMap({
      'costPriority': 1,
      'speedPriority': 0,
      'intelligencePriority': 1,
    });

    expect(prefs.costPriority, 1.0);
    expect(prefs.speedPriority, 0.0);
    expect(prefs.intelligencePriority, 1.0);
  });

  test('model preferences leave an absent priority null', () {
    final prefs = ModelPreferences.fromMap({});

    expect(prefs.costPriority, isNull);
    expect(prefs.speedPriority, isNull);
    expect(prefs.intelligencePriority, isNull);
  });

  test('model preferences read a fractional priority', () {
    final prefs = ModelPreferences.fromMap({
      'costPriority': 0.3,
      'speedPriority': 0.8,
      'intelligencePriority': 0.5,
    });

    expect(prefs.costPriority, 0.3);
    expect(prefs.speedPriority, 0.8);
    expect(prefs.intelligencePriority, 0.5);
  });

  test('temperature takes a fractional value', () {
    expect(
      CreateMessageRequest(
        messages: [],
        maxTokens: 1,
        temperature: 0.7,
      ).temperature,
      0.7,
    );
  });

  test('temperature is null when the map leaves it out', () {
    expect(
      CreateMessageRequest.fromMap({
        'messages': <Object?>[],
        'maxTokens': 1,
      }).temperature,
      isNull,
    );
  });

  test('temperature reads an integer as a double', () {
    expect(
      CreateMessageRequest.fromMap({
        'messages': <Object?>[],
        'maxTokens': 1,
        'temperature': 1,
      }).temperature,
      1.0,
    );
  });

  group('ToolUseContent', () {
    test('round trips through a map', () {
      final content = ToolUseContent(
        id: 'call-1',
        name: 'lookup',
        input: {'query': 'weather'},
      );
      final wire = content as Map<String, Object?>;

      expect(wire, {
        'type': 'tool_use',
        'id': 'call-1',
        'name': 'lookup',
        'input': {'query': 'weather'},
      });

      final decoded = ToolUseContent.fromMap(wire);
      expect(decoded.type, wire['type']);
      expect(decoded.id, 'call-1');
      expect(decoded.name, 'lookup');
      expect(decoded.input, {'query': 'weather'});

      final asContent = SamplingMessageContentBlock.fromMap(wire);
      expect(asContent.isToolUse, isTrue);
      expect(asContent.isToolResult, isFalse);
    });

    test('writes metadata when provided', () {
      final meta = Meta.fromMap({'source': 'tool'});
      final content = ToolUseContent(
        id: 'call-1',
        name: 'lookup',
        input: {},
        meta: meta,
      );

      expect(content as Map<String, Object?>, {
        'type': 'tool_use',
        'id': 'call-1',
        'name': 'lookup',
        'input': <String, Object?>{},
        '_meta': {'source': 'tool'},
      });
      expect(
        ToolUseContent.fromMap(content as Map<String, Object?>).meta,
        meta,
      );
    });
  });

  group('ToolResultContent', () {
    test('round trips through a map', () {
      final text = TextContent(text: 'done');
      final result = ToolResultContent(toolUseId: 'call-1', content: [text]);
      final wire = result as Map<String, Object?>;

      expect(wire, {
        'type': 'tool_result',
        'toolUseId': 'call-1',
        'content': [text],
      });

      final decoded = ToolResultContent.fromMap(wire);
      expect(decoded.type, wire['type']);
      expect(decoded.toolUseId, 'call-1');
      expect(decoded.content, hasLength(1));
      final decodedContent = decoded.content.single;
      expect(decodedContent.isText, isTrue);
      expect((decodedContent as TextContent).text, 'done');
      expect(decoded.structuredContent, isNull);
      expect(decoded.isError, isNull);

      final asContent = SamplingMessageContentBlock.fromMap(wire);
      expect(asContent.isToolResult, isTrue);
      expect(asContent.isToolUse, isFalse);
    });

    test('omits absent optional fields', () {
      final result = ToolResultContent(
        toolUseId: 'call-1',
        content: [TextContent(text: 'done')],
      );

      final wire = result as Map<String, Object?>;
      expect(wire.keys.toSet(), {'type', 'toolUseId', 'content'});
      expect(result.structuredContent, isNull);
      expect(result.isError, isNull);
      expect(result.meta, isNull);
    });

    test('reads optional fields when provided', () {
      final structuredContent = {'answer': '42'};
      final meta = Meta.fromMap({'source': 'tool'});
      final result = ToolResultContent(
        toolUseId: 'call-1',
        content: [TextContent(text: 'done')],
        structuredContent: structuredContent,
        isError: true,
        meta: meta,
      );

      expect(result as Map<String, Object?>, {
        'type': 'tool_result',
        'toolUseId': 'call-1',
        'content': [TextContent(text: 'done')],
        'structuredContent': structuredContent,
        'isError': true,
        '_meta': {'source': 'tool'},
      });
      expect(result.structuredContent, structuredContent);
      expect(result.isError, isTrue);
      expect(result.meta, meta);
    });

    test('throws when content is missing', () {
      expect(
        () =>
            ToolResultContent.fromMap({
              'type': 'tool_result',
              'toolUseId': 'call-1',
            }).content,
        throwsArgumentError,
      );
    });
  });

  test('server can request LLM messages from the client', () async {
    final environment = TestEnvironment(
      SamplingTestMCPClient(),
      TestMCPServer.new,
    );
    await environment.initializeServer();
    final server = environment.server;
    expect(server.clientCapabilities.sampling, isNotNull);

    final client = environment.client;
    final expectedResult =
        client.nextResult = CreateMessageResult(
          role: Role.assistant,
          content: [TextContent(text: 'Hello')],
          model: 'fakeModel',
        );

    expect(
      await server.sendRequest<CreateMessageResult>(
        CreateMessageRequest.methodName,
        CreateMessageRequest(messages: [], maxTokens: 100),
      ),
      expectedResult,
    );
  });

  test('reading tool content as plain content is refused', () {
    final wire = {
      'type': ToolUseContent.expectedType,
      'id': 'call-1',
      'name': 'greet',
    };

    expect(() => Content.fromMap(wire), throwsA(isA<AssertionError>()));
    expect(SamplingMessageContentBlock.fromMap(wire).isToolUse, isTrue);
  });
}

final class SamplingTestMCPClient extends TestMCPClient with SamplingSupport {
  /// Must be assign prior to sending a [CreateMessageRequest], and will be used
  /// as the response to the next request.
  CreateMessageResult? nextResult;

  @override
  FutureOr<CreateMessageResult> handleCreateMessage(
    CreateMessageRequest request,
    Implementation serverInfo,
  ) {
    if (nextResult case final result?) {
      nextResult = null;
      return result;
    } else {
      throw StateError('Must assign `nextResult` before issuing requests');
    }
  }
}
