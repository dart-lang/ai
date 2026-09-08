// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

const _protocolVersion = '2026-07-28';
// The transport does not support this version. It comes first in the
// server's supported list, so the fixture has to look past it.
const _olderVersion = '2025-11-25';
const _addNumbersTool = 'add_numbers';
const _scenarioVariable = 'MCP_CONFORMANCE_SCENARIO';
// An input request and its answer share one key.
const _formKey = 'form';

void main() {
  group('conformance client', () {
    late HttpServer server;
    late Uri endpoint;
    late List<_Received> received;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      endpoint = Uri.http('${server.address.host}:${server.port}', '/mcp');
      received = [];
      addTearDown(() => server.close(force: true));
    });

    /// Answers each request with [reply], after recording it.
    void serve(
      Map<String, Object?>? Function(_Received request, int count) reply,
    ) {
      server.listen((request) async {
        final body =
            jsonDecode(await utf8.decodeStream(request))
                as Map<String, Object?>;
        // A notification carries no id and gets no reply.
        if (!body.containsKey('id')) {
          request.response.statusCode = HttpStatus.accepted;
          await request.response.close();
          return;
        }
        final entry = _Received(
          method: body['method'] as String,
          version: request.headers.value('MCP-Protocol-Version'),
          params: body['params'] as Map<String, Object?>? ?? const {},
        );
        received.add(entry);
        final answer = reply(entry, received.length);
        request.response
          ..statusCode =
              answer?['error'] == null ? HttpStatus.ok : HttpStatus.badRequest
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'jsonrpc': '2.0', 'id': body['id'], ...?answer}));
        await request.response.close();
      });
    }

    test('lists and calls the tool its scenario names', () async {
      serve((request, _) => _result(request.method));

      await _runFixture(endpoint, 'tools_call');

      expect(received.map((request) => request.method), [
        'tools/list',
        'tools/call',
      ]);
      expect(received.last.params['name'], _addNumbersTool);
      expect(received.last.params['arguments'], {'a': 5, 'b': 7});
    });

    test('retries on a version the transport supports', () async {
      serve(
        (request, count) =>
            count == 1
                ? {
                  'error': {
                    'code': -32022,
                    'message': 'Unsupported protocol version',
                    // The rejected version comes first, so a fixture that
                    // takes the first name it is given picks a version the
                    // transport cannot open.
                    'data': {
                      'supported': [_olderVersion, _protocolVersion],
                      'requested': request.version,
                    },
                  },
                }
                : _result(request.method),
      );

      await _runFixture(endpoint, 'tools_call');

      expect(received.map((request) => request.method), [
        'tools/list',
        'tools/list',
        'tools/call',
      ]);
      expect(received.last.version, _protocolVersion);
    });

    test('answers each elicitation property with its declared type', () async {
      serve(
        (request, count) =>
            count == 2
                ? {
                  'result': {
                    'resultType': 'input_required',
                    'inputRequests': {
                      _formKey: {
                        'method': 'elicitation/create',
                        'params': {
                          'mode': 'form',
                          'message': 'conformance',
                          'requestedSchema': {
                            'type': 'object',
                            'properties': {
                              'flag': {'type': 'boolean'},
                              'count': {'type': 'integer'},
                              'ratio': {'type': 'number'},
                              'label': {'type': 'string'},
                            },
                          },
                        },
                      },
                    },
                  },
                }
                : _result(request.method),
      );

      await _runFixture(endpoint, 'tools_call');

      final responses =
          received.last.params['inputResponses'] as Map<String, Object?>;
      final answer = responses[_formKey] as Map<String, Object?>;
      expect(answer['action'], 'accept');
      // The value has to carry the declared type. An answer of the
      // wrong type still fills the form, and a scenario that only checks for
      // an accept would score it as a pass.
      expect(answer['content'], {
        'flag': isA<bool>(),
        'count': isA<int>(),
        'ratio': isA<double>(),
        'label': isA<String>(),
      });
    });
    // Once compiled, `Platform.resolvedExecutable` is this test's own
    // binary, so there is nothing to start the fixture with.
  }, testOn: '!exe');
}

/// A request the fixture put on the wire.
final class _Received {
  _Received({
    required this.method,
    required this.version,
    required this.params,
  });

  final String method;
  final String? version;
  final Map<String, Object?> params;
}

/// A well-formed result for a [method] request.
Map<String, Object?> _result(String method) => {
  'result': switch (method) {
    'tools/call' => {
      'content': [
        {'type': 'text', 'text': '12'},
      ],
    },
    _ => {
      'tools': [
        {
          'name': _addNumbersTool,
          'inputSchema': {'type': 'object'},
        },
      ],
    },
  },
};

/// Runs the fixture against [endpoint] as the suite would, and expects it to
/// succeed.
///
/// Reports what the fixture wrote before the runner's 30 second default, since
/// one that neither finishes nor exits leaves nothing behind to read. The wait
/// is close to that default so that a loaded bot still gets to finish.
Future<void> _runFixture(Uri endpoint, String scenario) async {
  final process = await Process.start(
    Platform.resolvedExecutable,
    ['tool/conformance_client.dart', endpoint.toString()],
    workingDirectory: Directory.current.path,
    environment: {_scenarioVariable: scenario},
  );
  // A failure before the wait below leaves the child running otherwise.
  addTearDown(process.kill);
  final output = StringBuffer();
  final drained = Future.wait([
    process.stdout.transform(utf8.decoder).forEach(output.write),
    process.stderr.transform(utf8.decoder).forEach(output.write),
  ]);
  const timedOut = -1;
  final code = await process.exitCode.timeout(
    const Duration(seconds: 25),
    onTimeout: () {
      process.kill();
      return timedOut;
    },
  );
  await drained;
  if (code == timedOut) fail('The fixture never exited. It wrote: $output');
  expect(code, 0, reason: output.toString());
}
