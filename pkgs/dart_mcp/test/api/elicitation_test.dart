// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/server.dart';
import 'package:test/test.dart';

import '../test_utils.dart';

// Fixture from the 2026-07-28 PrimitiveSchemaDefinition union.
// https://raw.githubusercontent.com/modelcontextprotocol/modelcontextprotocol/main/schema/2026-07-28/schema.json
const _validMultiSelectSchemas = <Map<String, Object?>>[
  <String, Object?>{
    'type': 'array',
    'items': <String, Object?>{
      'type': 'string',
      'enum': <Object?>['red', 'green'],
    },
  },
  <String, Object?>{
    'type': 'array',
    'items': <String, Object?>{
      'anyOf': <Object?>[
        <String, Object?>{'const': '#FF0000', 'title': 'Red'},
      ],
    },
  },
];

// TitledSingleSelectEnumSchema at the pinned canonical schema revision.
// https://github.com/modelcontextprotocol/modelcontextprotocol/blob/84d845729393f79b3fd3d392aa17cb86f5b6f95c/schema/2026-07-28/schema.json#L3571-L3617
const _titledSingleSelectSchema = <String, Object?>{
  'type': 'string',
  'title': 'Choice',
  'description': 'Choose one option',
  'default': 'b',
  'oneOf': <Object?>[
    <String, Object?>{'const': 'a', 'title': 'A'},
    <String, Object?>{'const': 'b', 'title': 'B'},
  ],
};

void main() {
  group('elicitation', () {
    test('a result without form data carries no content key', () {
      for (final action in [
        ElicitationAction.decline,
        ElicitationAction.cancel,
      ]) {
        expect(ElicitResult(action: action) as Map<String, Object?>, {
          'action': action.name,
        });
      }
      expect(
        ElicitResult(
              action: ElicitationAction.accept,
              content: {'answer': 'yes'},
            )
            as Map<String, Object?>,
        {
          'action': 'accept',
          'content': {'answer': 'yes'},
        },
      );
    });

    test('titled enum JSON round trip', () {
      for (final property in <Schema>[
        EnumSchema.titledSingleSelect(
          title: 'Choice',
          description: 'Choose one option',
          defaultValue: 'b',
          values: [
            EnumValueWithTitle(constValue: 'a', title: 'A'),
            EnumValueWithTitle(constValue: 'b', title: 'B'),
          ],
        ),
        TitledSingleSelectEnumSchema.fromMap(_titledSingleSelectSchema),
      ]) {
        expect(property as Map<String, Object?>, _titledSingleSelectSchema);
        final requestedSchema = ObjectSchema(
          properties: {'selection': property},
        );
        expect(ElicitRequest.validateRequestedSchema(requestedSchema), isTrue);

        final request = ElicitRequest.form(
          message: 'Choose an option',
          requestedSchema: requestedSchema,
        );
        final wire = jsonDecode(jsonEncode(request)) as Map<String, Object?>;
        expect(wire, {
          'mode': 'form',
          'message': 'Choose an option',
          'requestedSchema': {
            'type': 'object',
            'properties': {'selection': _titledSingleSelectSchema},
          },
        });

        final decoded = ObjectSchema.fromMap(
          wire['requestedSchema'] as Map<String, Object?>,
        );
        expect(ElicitRequest.validateRequestedSchema(decoded), isTrue);
        final restored = TitledSingleSelectEnumSchema.fromMap(
          decoded.properties!['selection']! as Map<String, Object?>,
        );
        expect(restored.defaultValue, 'b');
        expect(restored.values.map((value) => value.constValue), ['a', 'b']);
        expect(restored.values.map((value) => value.title), ['A', 'B']);
      }
    });

    test('titled enum option extensions', () {
      for (final options in <List<Object?>>[
        [],
        [
          {
            'const': 'a',
            'title': 'A',
            'description': 'Option detail',
            'x-extra': 'extra',
          },
        ],
        [
          {'const': 'a', 'title': 'A'},
          {'const': 'a', 'title': 'A'},
        ],
      ]) {
        final property = <String, Object?>{'type': 'string', 'oneOf': options};
        final expected = jsonDecode(jsonEncode(property));
        final requestedSchema = ObjectSchema(
          properties: {'selection': Schema.fromMap(property)},
        );
        expect(ElicitRequest.validateRequestedSchema(requestedSchema), isTrue);
        final request = ElicitRequest.form(
          message: 'Choose an option',
          requestedSchema: requestedSchema,
        );
        expect(
          jsonDecode(
            jsonEncode(request.requestedSchema!.properties!['selection']),
          ),
          expected,
        );
      }
    });

    test('invalid titled enum shapes', () {
      for (final oneOf in <Object>[
        'a',
        {'const': 'a', 'title': 'A'},
        <Object>{
          {'const': 'a', 'title': 'A'},
        },
        ['a'],
        [null],
        [
          {'type': 'string'},
        ],
        [
          {'title': 'A'},
        ],
        [
          {'const': 'a'},
        ],
        [
          {'const': 1, 'title': 'A'},
        ],
        [
          {'const': 'a', 'title': 1},
        ],
        [
          {'const': null, 'title': 'A'},
        ],
        [
          {'const': 'a', 'title': null},
        ],
        [
          {
            'const': {'nested': 'value'},
            'title': 'A',
          },
        ],
        [
          {'const': 'a', 'title': 'A'},
          {'type': 'string'},
        ],
      ]) {
        final requestedSchema = ObjectSchema(
          properties: {
            'selection': Schema.fromMap({'type': 'string', 'oneOf': oneOf}),
          },
        );
        expect(
          ElicitRequest.validateRequestedSchema(requestedSchema),
          isFalse,
          reason: 'oneOf: $oneOf',
        );
      }

      for (final type in <Object?>[
        null,
        'unknown',
        'number',
        'integer',
        'boolean',
        'object',
        'array',
        'null',
        'enum',
        7,
        <Object?>['string'],
      ]) {
        final requestedSchema = ObjectSchema(
          properties: {
            'selection': Schema.fromMap({
              if (type != null) 'type': type,
              'oneOf': _titledSingleSelectSchema['oneOf'],
            }),
          },
        );
        expect(
          ElicitRequest.validateRequestedSchema(requestedSchema),
          isFalse,
          reason: 'type: $type',
        );
      }
    });

    test('titled enums reject other combinators', () {
      for (final base in <Map<String, Object?>>[
        {'type': 'string'},
        _titledSingleSelectSchema,
      ]) {
        for (final key in ['allOf', 'anyOf', 'not']) {
          final requestedSchema = ObjectSchema(
            properties: {
              'selection': Schema.fromMap({
                ...base,
                key: <Object?>[
                  <String, Object?>{'type': 'string'},
                ],
              }),
            },
          );
          expect(
            ElicitRequest.validateRequestedSchema(requestedSchema),
            isFalse,
            reason: key,
          );
        }
      }
    });

    test('titled enum preserves later validation', () {
      expect(
        ElicitRequest.validateRequestedSchema(
          ObjectSchema(
            properties: {
              'selection': Schema.fromMap(_titledSingleSelectSchema),
              'nested': ObjectSchema(properties: {'child': StringSchema()}),
            },
          ),
        ),
        isFalse,
      );
    });

    test('a form takes both multi-select enum schemas', () {
      for (final schema in _validMultiSelectSchemas) {
        expect(
          () => ElicitRequest.form(
            message: 'Pick your colours',
            requestedSchema: ObjectSchema(
              properties: {'selection': Schema.fromMap(schema)},
            ),
          ),
          returnsNormally,
        );
      }
    });

    test('refuses arrays that are not multi-select enums', () {
      for (final property in [
        // Items the client would have to type into, not choose from.
        Schema.list(items: Schema.string()),
        // The items key holds a value, not a schema.
        Schema.fromMap({'type': 'array', 'items': 'red'}),
        // The values are strings, but the item type is not.
        Schema.fromMap({
          'type': 'array',
          'items': {
            'type': 'number',
            'enum': ['red', 'green'],
          },
        }),
        // The item type says string. The values are numbers.
        Schema.fromMap({
          'type': 'array',
          'items': {
            'type': 'string',
            'enum': [1, 2],
          },
        }),
        // One value where the spec asks for a list of them.
        Schema.fromMap({
          'type': 'array',
          'items': {'type': 'string', 'enum': 'red'},
        }),
        // A Set is iterable but is not a JSON array.
        Schema.fromMap({
          'type': 'array',
          'items': {
            'type': 'string',
            'enum': {'red', 'green'},
          },
        }),
        // A titled entry pairs a const with a title. This one has no const.
        Schema.fromMap({
          'type': 'array',
          'items': {
            'anyOf': [
              {'title': 'Red'},
            ],
          },
        }),
        // And this one has no title.
        Schema.fromMap({
          'type': 'array',
          'items': {
            'anyOf': [
              {'const': '#FF0000'},
            ],
          },
        }),
        // A bare value in `anyOf` is not a titled entry at all.
        Schema.fromMap({
          'type': 'array',
          'items': {
            'anyOf': ['red'],
          },
        }),
        // One entry sitting in `anyOf` where a list belongs.
        Schema.fromMap({
          'type': 'array',
          'items': {
            'anyOf': {'const': '#FF0000', 'title': 'Red'},
          },
        }),
        // A Set of titled values is not a JSON array.
        Schema.fromMap({
          'type': 'array',
          'items': {
            'anyOf': {
              {'const': '#FF0000', 'title': 'Red'},
            },
          },
        }),
      ]) {
        expect(
          () => ElicitRequest.form(
            message: 'Pick your colours',
            requestedSchema: ObjectSchema(properties: {'freeform': property}),
          ),
          throwsA(isA<AssertionError>()),
        );
      }
    }, testOn: '!exe');

    test('refuses a later invalid property', () {
      expect(
        () => ElicitRequest.form(
          message: 'Pick your colours',
          requestedSchema: ObjectSchema(
            properties: {
              'selection': Schema.fromMap(_validMultiSelectSchemas.first),
              'nested': ObjectSchema(),
            },
          ),
        ),
        throwsA(isA<AssertionError>()),
      );
    }, testOn: '!exe');

    test('server can elicit information from client', () async {
      final elicitationCompleter = Completer<ElicitResult>();
      final environment = TestEnvironment(
        TestMCPClientWithElicitationSupport(
          elicitationHandler: (request) {
            return elicitationCompleter.future;
          },
        ),
        TestMCPServerWithElicitationRequestSupport.new,
      );
      final server = environment.server;
      unawaited(server.initialized);
      await environment.serverConnection.initialize(
        InitializeRequest(
          protocolVersion: ProtocolVersion.lastLegacyVersion,
          capabilities: environment.client.capabilities,
          clientInfo: environment.client.implementation,
        ),
      );

      final elicitationRequest = server.sendRequest<ElicitResult>(
        ElicitRequest.methodName,
        ElicitRequest.form(
          message: 'What is your name?',
          requestedSchema: ObjectSchema(
            properties: {'name': StringSchema(description: 'Your name')},
            required: ['name'],
          ),
        ),
      );

      elicitationCompleter.complete(
        ElicitResult(
          action: ElicitationAction.accept,
          content: {'name': 'John Doe'},
        ),
      );

      final result = await elicitationRequest;
      expect(result.action, ElicitationAction.accept);
      expect(result.content, {'name': 'John Doe'});
    });
  });
}

final class TestMCPClientWithElicitationSupport extends TestMCPClient
    with ElicitationSupport {
  TestMCPClientWithElicitationSupport({required this.elicitationHandler});

  FutureOr<ElicitResult> Function(ElicitRequest request) elicitationHandler;

  @override
  FutureOr<ElicitResult> handleElicitation(ElicitRequest request, _) {
    return elicitationHandler(request);
  }
}

base class TestMCPServerWithElicitationRequestSupport extends TestMCPServer
    with LoggingSupport, ElicitationRequestSupport {
  TestMCPServerWithElicitationRequestSupport(super.channel);
}
