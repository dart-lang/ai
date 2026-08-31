// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/server.dart';
import 'package:test/test.dart';

import '../test_utils.dart';

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

    test('a multi-select enum is a schema a client can be asked for', () {
      // Both schemas the spec lists, see
      // https://modelcontextprotocol.io/specification/2026-07-28/client/elicitation.
      expect(
        () => ElicitRequest.form(
          message: 'Pick your colours',
          requestedSchema: ObjectSchema(
            properties: {
              'bare': UntitledMultiSelectEnumSchema(
                values: ['red', 'green'],
                minItems: 1,
              ),
              'titled': TitledMultiSelectEnumSchema(
                values: [
                  EnumValueWithTitle(title: 'Red', constValue: '#FF0000'),
                ],
              ),
            },
          ),
        ),
        returnsNormally,
      );
    });

    test('an array that is not a multi-select enum is refused', () {
      for (final property in [
        // Items the client would have to type into, not choose from.
        Schema.list(items: Schema.string()),
        // No items at all, so nothing names the values.
        Schema.list(),
        // Values named, but the spec asks for strings.
        Schema.fromMap({
          'type': 'array',
          'items': {
            'type': 'number',
            'enum': [1, 2],
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
        // Objects standing in for the strings.
        Schema.fromMap({
          'type': 'array',
          'items': {
            'type': 'string',
            'enum': [
              {'a': 1},
            ],
          },
        }),
        // One value where the spec asks for a list of them.
        Schema.fromMap({
          'type': 'array',
          'items': {'type': 'string', 'enum': 'red'},
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
          protocolVersion: ProtocolVersion.latestSupported,
          capabilities: environment.client.capabilities,
          clientInfo: environment.client.implementation,
        ),
      );

      final elicitationRequest = server.elicit(
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
