// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:dart_mcp/server.dart';
import 'package:dart_mcp/src/client/client.dart';
import 'package:test/test.dart';

import '../test_utils.dart';

void main() {
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
          content: TextContent(text: 'Hello'),
          model: 'fakeModel',
        );

    expect(
      await server.createMessage(
        CreateMessageRequest(messages: [], maxTokens: 100),
      ),
      expectedResult,
    );
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
