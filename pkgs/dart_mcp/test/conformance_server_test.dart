// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:async/async.dart';
import 'package:test/test.dart';

const _protocolVersion = '2026-07-28';
const _simpleTextTool = 'test_simple_text';
const _inputElicitationTool = 'test_input_required_result_elicitation';
const _inputStateTool = 'test_input_required_result_request_state';
const _inputTamperedTool = 'test_input_required_result_tampered_state';
const _templateUri = 'test://template/{id}/data';
const _expandedTemplateUri = 'test://template/123/data';
const _simplePrompt = 'test_simple_prompt';
const _toolChangeTool = 'test_trigger_tool_change';
const _promptChangeTool = 'test_trigger_prompt_change';
const _subscriptionIdMeta = 'io.modelcontextprotocol/subscriptionId';
const _formElicitationCapabilities = <String, Object?>{
  'elicitation': <String, Object?>{'form': <String, Object?>{}},
};

void main() {
  group('conformance server', () {
    late Process process;
    late StreamSubscription<String> errorSubscription;
    late Uri endpoint;

    setUpAll(() async {
      process = await Process.start(Platform.resolvedExecutable, [
        'tool/conformance_server.dart',
      ], workingDirectory: Directory.current.path);
      final errors = StringBuffer();
      errorSubscription = process.stderr
          .transform(utf8.decoder)
          .listen(errors.write);

      // Take a list instead of the first element, since a server that exits
      // before printing closes the stream empty, and reading the first element
      // of an empty stream throws past the timeout below with stderr lost.
      final reported = await process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .take(1)
          .toList()
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () => fail('Server did not report an endpoint: $errors'),
          );
      if (reported.isEmpty) {
        fail('Server exited before reporting an endpoint: $errors');
      }
      endpoint = Uri.parse(reported.single);
    });

    tearDownAll(() async {
      process.kill();
      await process.exitCode.timeout(const Duration(seconds: 10));
      await errorSubscription.cancel();
    });

    test('lists and calls its tool fixtures', () async {
      final tools = await _post(endpoint, 'tools/list');
      final toolsResult = tools['result'] as Map<String, Object?>;
      final toolList = toolsResult['tools'] as List<Object?>;
      expect(toolList, contains(containsPair('name', _simpleTextTool)));
      expect(toolList, contains(containsPair('name', _inputElicitationTool)));
      expect(toolList, contains(containsPair('name', _inputStateTool)));

      final tool = await _post(
        endpoint,
        'tools/call',
        params: {'name': _simpleTextTool, 'arguments': <String, Object?>{}},
      );
      final toolResult = tool['result'] as Map<String, Object?>;
      expect(toolResult['isError'], isNot(true));
      final toolContent = toolResult['content'] as List<Object?>;
      expect(toolContent, hasLength(1));
      expect(toolContent.single, {
        'type': 'text',
        'text': 'This is a simple text response for testing.',
      });
    });

    test('lists and reads its resource template fixture', () async {
      final templates = await _post(endpoint, 'resources/templates/list');
      final result = templates['result'] as Map<String, Object?>;
      final resourceTemplates = result['resourceTemplates'] as List<Object?>;
      expect(resourceTemplates, hasLength(1));
      expect(
        resourceTemplates.single,
        containsPair('uriTemplate', _templateUri),
      );

      final resource = await _post(
        endpoint,
        'resources/read',
        params: {'uri': _expandedTemplateUri},
      );
      final resourceResult = resource['result'] as Map<String, Object?>;
      final contents = resourceResult['contents'] as List<Object?>;
      final content = contents.single as Map<String, Object?>;
      expect(content['uri'], _expandedTemplateUri);
      expect(jsonDecode(content['text'] as String), {
        'id': '123',
        'templateTest': true,
        'data': 'Data for ID: 123',
      });
    });

    test('lists and renders its prompt fixture', () async {
      final prompts = await _post(endpoint, 'prompts/list');
      final promptsResult = prompts['result'] as Map<String, Object?>;
      final promptList = promptsResult['prompts'] as List<Object?>;
      expect(promptList, contains(containsPair('name', _simplePrompt)));

      final prompt = await _post(
        endpoint,
        'prompts/get',
        params: {'name': _simplePrompt},
      );
      final promptResult = prompt['result'] as Map<String, Object?>;
      final messages = promptResult['messages'] as List<Object?>;
      expect(messages, hasLength(1));
      expect(messages.single, {
        'role': 'user',
        'content': {
          'type': 'text',
          'text': 'This is a simple prompt for testing.',
        },
      });
    });

    test('answers with input requests and honours the retry', () async {
      final elicitation = await _post(
        endpoint,
        'tools/call',
        params: {
          'name': _inputElicitationTool,
          'arguments': <String, Object?>{},
        },
        capabilities: _formElicitationCapabilities,
      );
      final elicitationResult = elicitation['result'] as Map<String, Object?>;
      final inputRequests =
          elicitationResult['inputRequests'] as Map<String, Object?>;
      expect(
        inputRequests['user_name'],
        containsPair('method', 'elicitation/create'),
      );

      final state = await _post(
        endpoint,
        'tools/call',
        params: {'name': _inputStateTool, 'arguments': <String, Object?>{}},
        capabilities: _formElicitationCapabilities,
      );
      final stateResult = state['result'] as Map<String, Object?>;
      final requestState = stateResult['requestState'] as String;
      final completedState = await _post(
        endpoint,
        'tools/call',
        params: {
          'name': _inputStateTool,
          'arguments': <String, Object?>{},
          'inputResponses': {
            'confirm': {
              'action': 'accept',
              'content': {'ok': true},
            },
          },
          'requestState': requestState,
        },
        capabilities: _formElicitationCapabilities,
      );
      final completedStateResult =
          completedState['result'] as Map<String, Object?>;
      final completedStateContent =
          completedStateResult['content'] as List<Object?>;
      expect(
        completedStateContent.single,
        containsPair(
          'text',
          'state-ok: requestState verified and confirmation received',
        ),
      );
    });

    test('refuses a request state whose signature was changed', () async {
      final issued = await _post(
        endpoint,
        'tools/call',
        params: {'name': _inputTamperedTool, 'arguments': <String, Object?>{}},
        capabilities: _formElicitationCapabilities,
      );
      final requestState =
          (issued['result'] as Map<String, Object?>)['requestState'] as String;
      final separator = requestState.lastIndexOf('.');
      final signature = requestState.substring(separator + 1);
      final tampered =
          requestState.substring(0, separator + 1) +
          (signature[0] == 'A' ? 'B' : 'A') +
          signature.substring(1);

      final refused = await _post(
        endpoint,
        'tools/call',
        params: {
          'name': _inputTamperedTool,
          'arguments': <String, Object?>{},
          'inputResponses': {
            'confirm': {
              'action': 'accept',
              'content': {'ok': true},
            },
          },
          'requestState': tampered,
        },
        capabilities: _formElicitationCapabilities,
        expectedStatus: HttpStatus.badRequest,
      );

      expect(refused['result'], isNull);
      expect(
        (refused['error'] as Map<String, Object?>)['message'],
        contains('failed integrity validation'),
      );
    });

    test('delivers a list change from another request on a listen '
        'stream', () async {
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.postUrl(endpoint);
      request.headers
        ..set(HttpHeaders.contentTypeHeader, 'application/json')
        ..set(HttpHeaders.acceptHeader, 'application/json, text/event-stream')
        ..set('Mcp-Protocol-Version', _protocolVersion)
        ..set('Mcp-Method', 'subscriptions/listen');
      request.write(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 7,
          'method': 'subscriptions/listen',
          'params': {
            'notifications': {
              'toolsListChanged': true,
              'promptsListChanged': true,
            },
            '_meta': {
              'io.modelcontextprotocol/protocolVersion': _protocolVersion,
              'io.modelcontextprotocol/clientCapabilities': <String, Object?>{},
            },
          },
        }),
      );
      final response = await request.close();
      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers.contentType?.mimeType, 'text/event-stream');
      final events = StreamQueue(
        response
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .where((line) => line.startsWith('data: '))
            .map(
              (line) =>
                  jsonDecode(line.substring('data: '.length))
                      as Map<String, Object?>,
            ),
      );
      // Cancel immediately. A plain cancel waits for the pending request.
      addTearDown(() => events.cancel(immediate: true));

      final acknowledgement = await _next(events);
      expect(
        acknowledgement['method'],
        'notifications/subscriptions/acknowledged',
      );
      // The subscription is named by the id of the request opening it.
      expect(_meta(acknowledgement), containsPair(_subscriptionIdMeta, 7));

      // Two more requests, each answered by its own server. Neither one holds
      // the stream open. The changes reach it through the transport.
      for (final trigger in [_toolChangeTool, _promptChangeTool]) {
        final triggered = await _post(
          endpoint,
          'tools/call',
          params: {'name': trigger, 'arguments': <String, Object?>{}},
        );
        expect(
          (triggered['result'] as Map<String, Object?>)['isError'],
          isNot(true),
        );
      }

      final changes = [await _next(events), await _next(events)];
      expect(changes.map((change) => change['method']), [
        'notifications/tools/list_changed',
        'notifications/prompts/list_changed',
      ]);
      for (final change in changes) {
        expect(_meta(change), containsPair(_subscriptionIdMeta, 7));
      }
    });
    // `Platform.resolvedExecutable` is this test's own binary once it is
    // compiled, so it cannot start the server the way it does on the VM.
  }, testOn: '!exe');
}

/// The `_meta` envelope of [notification]'s params.
Map<String, Object?> _meta(Map<String, Object?> notification) =>
    (notification['params'] as Map<String, Object?>)['_meta']
        as Map<String, Object?>;

/// The next event on [events]. Fails the test when the server never sends
/// one.
///
/// Fails with a message before the runner's 30 second default.
Future<Map<String, Object?>> _next(StreamQueue<Map<String, Object?>> events) =>
    events.next.timeout(
      const Duration(seconds: 20),
      onTimeout: () => fail('The listen stream sent no further event'),
    );

Future<Map<String, Object?>> _post(
  Uri endpoint,
  String method, {
  Map<String, Object?> params = const {},
  Map<String, Object?> capabilities = const {},
  int expectedStatus = HttpStatus.ok,
}) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(endpoint);
    request.headers
      ..set(HttpHeaders.contentTypeHeader, 'application/json')
      ..set(HttpHeaders.acceptHeader, 'application/json, text/event-stream')
      ..set('Mcp-Protocol-Version', _protocolVersion)
      ..set('Mcp-Method', method);
    final name = params['name'] ?? params['uri'];
    if (name is String) {
      request.headers.set('Mcp-Name', name);
    }
    request.write(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': 1,
        'method': method,
        'params': {
          ...params,
          '_meta': {
            'io.modelcontextprotocol/protocolVersion': _protocolVersion,
            'io.modelcontextprotocol/clientCapabilities': capabilities,
          },
        },
      }),
    );

    final response = await request.close();
    final responseText = await utf8.decodeStream(response);
    expect(response.statusCode, expectedStatus, reason: responseText);
    return jsonDecode(responseText) as Map<String, Object?>;
  } finally {
    client.close(force: true);
  }
}
