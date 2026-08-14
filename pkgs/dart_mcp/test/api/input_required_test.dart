// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dart_mcp/client.dart';
import 'package:test/test.dart';

void main() {
  group('InputRequest', () {
    test('writes the method next to the request it applies to', () {
      final sample = CreateMessageRequest(messages: [], maxTokens: 1);
      expect(InputRequest.sample(sample) as Map<String, Object?>, {
        'method': 'sampling/createMessage',
        'params': sample,
      });

      final elicit = ElicitRequest.form(
        message: 'What is your name?',
        requestedSchema: ObjectSchema(
          properties: {'name': StringSchema()},
          required: ['name'],
        ),
      );
      expect(InputRequest.elicit(elicit) as Map<String, Object?>, {
        'method': 'elicitation/create',
        'params': elicit,
      });

      final roots = ListRootsRequest();
      expect(InputRequest.listRoots(roots) as Map<String, Object?>, {
        'method': 'roots/list',
        'params': roots,
      });
    });

    test('reads back a request a server sent', () {
      final request = InputRequest.fromMap({
        'method': 'roots/list',
        'params': <String, Object?>{},
      });

      expect(request.method, 'roots/list');
      expect(request.params as Map<String, Object?>?, isEmpty);
    });

    test('tells the kinds apart by method', () {
      final elicit = InputRequest.elicit(
        ElicitRequest.form(
          message: 'What is your name?',
          requestedSchema: ObjectSchema(
            properties: {'name': StringSchema()},
            required: ['name'],
          ),
        ),
      );
      final sample = InputRequest.sample(
        CreateMessageRequest(messages: [], maxTokens: 1),
      );
      final roots = InputRequest.listRoots(ListRootsRequest());

      expect(
        [elicit.isElicit, elicit.isSample, elicit.isListRoots],
        [true, false, false],
      );
      expect(
        [sample.isElicit, sample.isSample, sample.isListRoots],
        [false, true, false],
      );
      expect(
        [roots.isElicit, roots.isSample, roots.isListRoots],
        [false, false, true],
      );
    });

    test('rejects a request with no method', () {
      expect(
        () => InputRequest.fromMap({'params': <String, Object?>{}}),
        throwsA(isA<AssertionError>()),
      );
      // A compiled executable has asserts stripped, so there is nothing to
      // catch there.
    }, testOn: '!exe');
  });

  group('InputRequiredResult', () {
    test('marks itself as the interim result type', () {
      expect(
        InputRequiredResult(requestState: 'opaque').resultType,
        'input_required',
      );
    });

    test('writes only the fields it is given', () {
      expect(
        InputRequiredResult(requestState: 'opaque') as Map<String, Object?>,
        {'resultType': 'input_required', 'requestState': 'opaque'},
      );
      expect(
        InputRequiredResult(
              inputRequests: {
                'roots': InputRequest.listRoots(ListRootsRequest()),
              },
            )
            as Map<String, Object?>,
        {
          'resultType': 'input_required',
          'inputRequests': {
            'roots': {'method': 'roots/list', 'params': <String, Object?>{}},
          },
        },
      );
    });

    test('reads back the requests a server sent', () {
      final result = InputRequiredResult.fromMap({
        'resultType': 'input_required',
        'inputRequests': {
          'roots': {'method': 'roots/list', 'params': <String, Object?>{}},
        },
        'requestState': 'opaque',
      });

      expect(result.inputRequests, hasLength(1));
      expect(result.inputRequests!['roots']!.method, 'roots/list');
      expect(result.requestState, 'opaque');
    });

    test('leaves both fields null when a server omits them', () {
      final result = InputRequiredResult.fromMap({
        'resultType': 'input_required',
      });

      expect(result.inputRequests, isNull);
      expect(result.requestState, isNull);
    });

    test('writes the metadata it is given', () {
      expect(
        InputRequiredResult(
              requestState: 'opaque',
              meta: Meta.fromMap({'io.modelcontextprotocol/serverInfo': {}}),
            )
            as Map<String, Object?>,
        containsPair(
          '_meta',
          containsPair('io.modelcontextprotocol/serverInfo', isEmpty),
        ),
      );
    });

    test('reports a malformed entry rather than throwing', () {
      final result = InputRequiredResult.fromMap({
        'resultType': 'input_required',
        'inputRequests': {'a': <String, Object?>{}},
      });
      final entry = result.inputRequests!['a']!;

      expect(entry.isElicit, isFalse);
      expect(entry.isSample, isFalse);
      expect(entry.isListRoots, isFalse);
    });

    test('rejects a result which asks for nothing', () {
      expect(InputRequiredResult.new, throwsA(isA<AssertionError>()));
      expect(
        () => InputRequiredResult(inputRequests: {}),
        throwsA(isA<AssertionError>()),
      );
    }, testOn: '!exe');
  });
}
