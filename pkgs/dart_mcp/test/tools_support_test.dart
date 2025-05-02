// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:dart_mcp/server.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  test('client can list and invoke tools from the server', () async {
    final environment = TestEnvironment(
      TestMCPClient(),
      TestMCPServerWithTools.new,
    );
    final initializeResult = await environment.initializeServer();
    expect(
      initializeResult.capabilities.tools,
      equals(Tools(listChanged: true)),
    );

    final serverConnection = environment.serverConnection;

    final toolsResult = await serverConnection.listTools();
    expect(toolsResult.tools.length, 1);

    final tool = toolsResult.tools.single;

    final result = await serverConnection.callTool(
      CallToolRequest(name: tool.name),
    );
    expect(result.isError, isNot(true));
    expect(result.content.single, TestMCPServerWithTools.helloWorldContent);

    expect(
      await serverConnection.listTools(ListToolsRequest()),
      toolsResult,
      reason: 'can list tools with a non-null request object',
    );
  });

  test('client can subscribe to tool list updates from the server', () async {
    final environment = TestEnvironment(
      TestMCPClient(),
      TestMCPServerWithTools.new,
    );
    await environment.initializeServer();

    final serverConnection = environment.serverConnection;
    final server = environment.server;

    expect(
      serverConnection.toolListChanged,
      emitsInOrder([
        ToolListChangedNotification(),
        ToolListChangedNotification(),
      ]),
    );

    server.registerTool(
      Tool(name: 'foo', inputSchema: ObjectSchema()),
      (_) => CallToolResult(content: []),
    );

    server.unregisterTool('foo');

    // Give the notifications time to be received.
    await pumpEventQueue();

    // Need to manually close so the stream matchers can complete.
    await environment.shutdown();
  });

  group('Schemas', () {
    test('ObjectSchema', () {
      final schema = ObjectSchema(
        title: 'Foo',
        description: 'Bar',
        patternProperties: {'^foo': StringSchema()},
        properties: {'foo': StringSchema(), 'bar': IntegerSchema()},
        required: ['foo'],
        additionalProperties: false,
        unevaluatedProperties: true,
        propertyNames: StringSchema(pattern: r'^[a-z]+$'),
        minProperties: 1,
        maxProperties: 2,
      );
      expect(schema, {
        'type': 'object',
        'title': 'Foo',
        'description': 'Bar',
        'patternProperties': {
          '^foo': {'type': 'string'},
        },
        'properties': {
          'foo': {'type': 'string'},
          'bar': {'type': 'integer'},
        },
        'required': ['foo'],
        'additionalProperties': false,
        'unevaluatedProperties': true,
        'propertyNames': {'type': 'string', 'pattern': r'^[a-z]+$'},
        'minProperties': 1,
        'maxProperties': 2,
      });
    });

    test('StringSchema', () {
      final schema = StringSchema(
        title: 'Foo',
        description: 'Bar',
        minLength: 1,
        maxLength: 10,
        pattern: r'^[a-z]+$',
      );
      expect(schema, {
        'type': 'string',
        'title': 'Foo',
        'description': 'Bar',
        'minLength': 1,
        'maxLength': 10,
        'pattern': r'^[a-z]+$',
      });
    });

    test('NumberSchema', () {
      final schema = NumberSchema(
        title: 'Foo',
        description: 'Bar',
        minimum: 1,
        maximum: 10,
        exclusiveMinimum: 0,
        exclusiveMaximum: 11,
        multipleOf: 2,
      );
      expect(schema, {
        'type': 'number',
        'title': 'Foo',
        'description': 'Bar',
        'minimum': 1,
        'maximum': 10,
        'exclusiveMinimum': 0,
        'exclusiveMaximum': 11,
        'multipleOf': 2,
      });
    });

    test('IntegerSchema', () {
      final schema = IntegerSchema(
        title: 'Foo',
        description: 'Bar',
        minimum: 1,
        maximum: 10,
        exclusiveMinimum: 0,
        exclusiveMaximum: 11,
        multipleOf: 2,
      );
      expect(schema, {
        'type': 'integer',
        'title': 'Foo',
        'description': 'Bar',
        'minimum': 1,
        'maximum': 10,
        'exclusiveMinimum': 0,
        'exclusiveMaximum': 11,
        'multipleOf': 2,
      });
    });

    test('BooleanSchema', () {
      final schema = BooleanSchema(title: 'Foo', description: 'Bar');
      expect(schema, {'type': 'boolean', 'title': 'Foo', 'description': 'Bar'});
    });

    test('NullSchema', () {
      final schema = NullSchema(title: 'Foo', description: 'Bar');
      expect(schema, {'type': 'null', 'title': 'Foo', 'description': 'Bar'});
    });

    test('ListSchema', () {
      final schema = ListSchema(
        title: 'Foo',
        description: 'Bar',
        items: StringSchema(),
        prefixItems: [IntegerSchema(), BooleanSchema()],
        unevaluatedItems: false,
        minItems: 1,
        maxItems: 10,
        uniqueItems: true,
      );
      expect(schema, {
        'type': 'array',
        'title': 'Foo',
        'description': 'Bar',
        'items': {'type': 'string'},
        'prefixItems': [
          {'type': 'integer'},
          {'type': 'boolean'},
        ],
        'unevaluatedItems': false,
        'minItems': 1,
        'maxItems': 10,
        'uniqueItems': true,
      });
    });

    test('Schema', () {
      final schema = Schema.combined(
        type: JsonType.bool,
        title: 'Foo',
        description: 'Bar',
        allOf: [StringSchema(), IntegerSchema()],
        anyOf: [StringSchema(), IntegerSchema()],
        oneOf: [StringSchema(), IntegerSchema()],
        not: [StringSchema()],
      );
      expect(schema, {
        'type': 'boolean',
        'title': 'Foo',
        'description': 'Bar',
        'allOf': [
          {'type': 'string'},
          {'type': 'integer'},
        ],
        'anyOf': [
          {'type': 'string'},
          {'type': 'integer'},
        ],
        'oneOf': [
          {'type': 'string'},
          {'type': 'integer'},
        ],
        'not': [
          {'type': 'string'},
        ],
      });
    });
  });
}

final class TestMCPServerWithTools extends TestMCPServer with ToolsSupport {
  TestMCPServerWithTools(super.channel);

  @override
  FutureOr<InitializeResult> initialize(InitializeRequest request) {
    registerTool(
      helloWorld,
      (_) => CallToolResult(content: [helloWorldContent]),
    );
    return super.initialize(request);
  }

  static final helloWorld = Tool(
    name: 'hello_world',
    description: 'Says hello world!',
    inputSchema: ObjectSchema(),
    annotations: ToolAnnotations(
      destructiveHint: false,
      idempotentHint: false,
      readOnlyHint: true,
      openWorldHint: false,
      title: 'Hello World',
    ),
  );

  static final helloWorldContent = TextContent(
    text: 'hello world!',
    annotations: Annotations(priority: 0.5, audience: [Role.user]),
  );
}
