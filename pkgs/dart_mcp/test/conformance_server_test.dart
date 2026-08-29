// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

const _protocolVersion = '2026-07-28';
const _simpleTextTool = 'test_simple_text';
const _inputElicitationTool = 'test_input_required_result_elicitation';
const _inputStateTool = 'test_input_required_result_request_state';
const _templateUri = 'test://template/{id}/data';
const _expandedTemplateUri = 'test://template/123/data';
const _simplePrompt = 'test_simple_prompt';
const _formElicitationCapabilities = <String, Object?>{
  'elicitation': <String, Object?>{'form': <String, Object?>{}},
};

void main() {
  test('conformance server advertises and serves fixture contracts', () async {
    final process = await Process.start(Platform.resolvedExecutable, [
      'tool/conformance_server.dart',
    ], workingDirectory: Directory.current.path);
    final errors = StringBuffer();
    final errorSubscription = process.stderr
        .transform(utf8.decoder)
        .listen(errors.write);
    addTearDown(() async {
      process.kill();
      await process.exitCode.timeout(const Duration(seconds: 10));
      await errorSubscription.cancel();
    });

    final endpoint = Uri.parse(
      await process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () => fail('Server did not report an endpoint: $errors'),
          ),
    );

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

    final templates = await _post(endpoint, 'resources/templates/list');
    final result = templates['result'] as Map<String, Object?>;
    final resourceTemplates = result['resourceTemplates'] as List<Object?>;
    expect(resourceTemplates, hasLength(1));
    expect(resourceTemplates.single, containsPair('uriTemplate', _templateUri));

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

    final elicitation = await _post(
      endpoint,
      'tools/call',
      params: {'name': _inputElicitationTool, 'arguments': <String, Object?>{}},
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
}

Future<Map<String, Object?>> _post(
  Uri endpoint,
  String method, {
  Map<String, Object?> params = const {},
  Map<String, Object?> capabilities = const {},
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
    expect(response.statusCode, HttpStatus.ok, reason: responseText);
    return jsonDecode(responseText) as Map<String, Object?>;
  } finally {
    client.close(force: true);
  }
}
