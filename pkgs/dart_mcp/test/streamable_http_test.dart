// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:dart_mcp/src/utils/constants.dart';
import 'package:dart_mcp/streamable_http.dart';
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:test/test.dart';

/// The protocol version this transport speaks.
const version = '2026-07-28';

/// The headers every POST carries, whatever its body is.
const transportHeaders = {
  'Content-Type': 'application/json',
  'Accept': 'application/json, text/event-stream',
};

void main() {
  late HttpServer httpServer;
  late Uri uri;
  final servers = <_HttpTestServer>[];
  final notifications = <Map<String, Object?>>[];

  setUp(() async {
    servers.clear();
    notifications.clear();
    httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    uri = Uri.http('${httpServer.address.host}:${httpServer.port}', '/mcp');
    httpServer.listen(
      (request) => handleStreamableHttpRequest(request, (channel) {
        final server = _HttpTestServer(channel);
        servers.add(server);
        return server;
      }, onNotification: notifications.add),
    );
    addTearDown(() => httpServer.close(force: true));
  });

  /// A request body for [method] carrying the standard envelope.
  Map<String, Object?> body(
    String method, {
    Object? id = 1,
    Map<String, Object?>? params,
    Object? bodyVersion,
    Object? capabilities = const <String, Object?>{},
  }) => {
    'jsonrpc': '2.0',
    if (id != null) 'id': id,
    'method': method,
    'params': {
      ...?params,
      Keys.meta: {
        Keys.protocolVersionMeta: bodyVersion ?? version,
        Keys.clientCapabilitiesMeta: capabilities,
      },
    },
  };

  /// The transport and mirrored headers for [method].
  Map<String, String> headers(
    String method, {
    String? headerVersion,
    String? headerMethod,
  }) => {
    ...transportHeaders,
    'Mcp-Protocol-Version': headerVersion ?? version,
    'Mcp-Method': headerMethod ?? method,
  };

  Future<(int, HttpHeaders, String)> post({
    Map<String, String> headers = const {},
    Object? json,
    String? raw,
    String method = 'POST',
  }) async {
    final client = HttpClient();
    addTearDown(client.close);
    final request = await client.openUrl(method, uri);
    headers.forEach(request.headers.set);
    if (raw != null || json != null) {
      request.write(raw ?? jsonEncode(json));
    }
    final response = await request.close();
    final text = await utf8.decodeStream(response);
    return (response.statusCode, response.headers, text);
  }

  Map<String, Object?> decode(String text) =>
      jsonDecode(text) as Map<String, Object?>;

  Object? errorCode(String text) =>
      (decode(text)['error'] as Map<String, Object?>?)?['code'];

  group('happy path', () {
    test('answers tools/list with JSON and server info', () async {
      final (status, responseHeaders, text) = await post(
        headers: headers('tools/list'),
        json: body('tools/list'),
      );
      expect(status, 200);
      expect(responseHeaders.contentType?.mimeType, 'application/json');
      expect(responseHeaders.contentType?.charset, 'utf-8');
      expect(responseHeaders.value('Mcp-Session-Id'), isNull);
      final response = decode(text);
      expect(response['id'], 1);
      final result = response['result'] as Map<String, Object?>;
      final tools = result['tools'] as List;
      expect(
        tools.map((tool) => (tool as Map<String, Object?>)['name']),
        contains('test/version'),
      );
      expect(
        (result['_meta']
            as Map<String, Object?>)['io.modelcontextprotocol/serverInfo'],
        isNotNull,
      );
    });

    test('answers tools/call with the tool result', () async {
      final (status, _, text) = await post(
        headers: {...headers('tools/call'), 'Mcp-Name': 'test/version'},
        json: body('tools/call', params: {'name': 'test/version'}),
      );
      expect(status, 200);
      final result = decode(text)['result'] as Map<String, Object?>;
      final content = result['content'] as List;
      expect((content.single as Map<String, Object?>)['text'], '1.2.3');
    });
  });

  group('notifications and responses', () {
    test('acknowledges a notification without headers or dispatch', () async {
      final (status, _, text) = await post(
        headers: transportHeaders,
        json: {'jsonrpc': '2.0', 'method': 'notifications/progress'},
      );
      expect(status, 202);
      expect(text, isEmpty);
      expect(servers, isEmpty);
    });

    test('acknowledges an unknown notification', () async {
      final (status, _, text) = await post(
        headers: headers('no/such/notification'),
        json: {'jsonrpc': '2.0', 'method': 'no/such/notification'},
      );
      expect(status, 202);
      expect(text, isEmpty);
      expect(servers, isEmpty);
    });

    test('rejects a JSON-RPC response body', () async {
      final (status, _, text) = await post(
        headers: transportHeaders,
        json: {'jsonrpc': '2.0', 'id': 1, 'result': <String, Object?>{}},
      );
      expect(status, 400);
      expect(errorCode(text), -32600);
      expect(servers, isEmpty);
    });

    test('rejects a message without a method before acknowledging', () async {
      // A body with neither an id nor a method is a notification by shape,
      // but the missing method is caught first, so it is a 400 not a 202.
      final (status, _, text) = await post(
        headers: transportHeaders,
        json: {'jsonrpc': '2.0'},
      );
      expect(status, 400);
      expect(errorCode(text), -32600);
      expect(servers, isEmpty);
    });

    test('rejects a non-string method', () async {
      final (status, _, text) = await post(
        headers: transportHeaders,
        json: {'jsonrpc': '2.0', 'id': 1, 'method': 42},
      );
      expect(status, 400);
      expect(errorCode(text), -32600);
    });

    test('rejects a scalar body', () async {
      final (status, _, text) = await post(
        headers: transportHeaders,
        raw: '42',
      );
      expect(status, 400);
      expect(errorCode(text), -32600);
    });
  });

  group('content negotiation', () {
    test('rejects a request without a Content-Type header', () async {
      final (status, _, text) = await post(
        headers: {
          'Accept': 'application/json, text/event-stream',
          'Mcp-Protocol-Version': version,
          'Mcp-Method': 'tools/list',
        },
        json: body('tools/list'),
      );
      expect(status, 415);
      expect(errorCode(text), -32020);
      expect(servers, isEmpty);
    });

    test('rejects a text/plain Content-Type', () async {
      final (status, responseHeaders, text) = await post(
        headers: {...headers('tools/list'), 'Content-Type': 'text/plain'},
        json: body('tools/list'),
      );
      expect(status, 415);
      expect(responseHeaders.contentType?.mimeType, 'application/json');
      expect(errorCode(text), -32020);
    });

    test('tolerates a charset on the Content-Type', () async {
      final (status, _, text) = await post(
        headers: {
          ...headers('tools/list'),
          'Content-Type': 'application/json; charset=utf-8',
        },
        json: body('tools/list'),
      );
      expect(status, 200);
      expect(errorCode(text), isNull);
    });

    test('rejects a request without an Accept header', () async {
      final (status, _, text) = await post(
        headers: {
          'Content-Type': 'application/json',
          'Mcp-Protocol-Version': version,
          'Mcp-Method': 'tools/list',
        },
        json: body('tools/list'),
      );
      expect(status, 406);
      expect(errorCode(text), -32020);
      expect(servers, isEmpty);
    });

    test('rejects an Accept header without text/event-stream', () async {
      final (status, responseHeaders, text) = await post(
        headers: {...headers('tools/list'), 'Accept': 'application/json'},
        json: body('tools/list'),
      );
      expect(status, 406);
      expect(responseHeaders.contentType?.mimeType, 'application/json');
      expect(errorCode(text), -32020);
    });

    test('rejects an Accept header without application/json', () async {
      final (status, _, text) = await post(
        headers: {...headers('tools/list'), 'Accept': 'text/event-stream'},
        json: body('tools/list'),
      );
      expect(status, 406);
      expect(errorCode(text), -32020);
    });

    test('accepts the */* wildcard', () async {
      final (status, _, text) = await post(
        headers: {...headers('tools/list'), 'Accept': '*/*'},
        json: body('tools/list'),
      );
      expect(status, 200);
      expect(errorCode(text), isNull);
    });

    test('accepts type wildcards with quality values', () async {
      final (status, _, text) = await post(
        headers: {
          ...headers('tools/list'),
          'Accept': 'application/*;q=0.9, text/*;q=0.8',
        },
        json: body('tools/list'),
      );
      expect(status, 200);
      expect(errorCode(text), isNull);
    });

    test('acknowledges a notification which accepts nothing', () async {
      // The Accept rule only applies to requests, which are the only messages
      // that get a body back.
      final (status, _, text) = await post(
        headers: {'Content-Type': 'application/json'},
        json: {'jsonrpc': '2.0', 'method': 'notifications/progress'},
      );
      expect(status, 202);
      expect(text, isEmpty);
    });
  });

  group('required headers', () {
    test('rejects a missing protocol version header', () async {
      final (status, _, text) = await post(
        headers: {...transportHeaders, 'Mcp-Method': 'tools/list'},
        json: body('tools/list'),
      );
      expect(status, 400);
      expect(errorCode(text), -32020);
    });

    test('rejects a header and body version mismatch', () async {
      final (status, _, text) = await post(
        headers: headers('tools/list'),
        json: body('tools/list', bodyVersion: '2025-06-18'),
      );
      expect(status, 400);
      expect(errorCode(text), -32020);
    });

    test('rejects a missing Mcp-Method header', () async {
      final (status, _, text) = await post(
        headers: {...transportHeaders, 'Mcp-Protocol-Version': version},
        json: body('tools/list'),
      );
      expect(status, 400);
      expect(errorCode(text), -32020);
    });

    test('rejects an Mcp-Method header mismatch', () async {
      final (status, _, text) = await post(
        headers: headers('tools/call'),
        json: body('tools/list'),
      );
      expect(status, 400);
      expect(errorCode(text), -32020);
      expect(servers, isEmpty);
    });

    test('compares Mcp-Method values case sensitively', () async {
      // Header names are case insensitive, header values are not.
      final (status, _, text) = await post(
        headers: {
          ...headers('tools/call', headerMethod: 'Tools/Call'),
          'Mcp-Name': 'test/version',
        },
        json: body('tools/call', params: {'name': 'test/version'}),
      );
      expect(status, 400);
      expect(errorCode(text), -32020);
      expect(servers, isEmpty);
    });

    test('rejects a tools/call without an Mcp-Name header', () async {
      final (status, _, text) = await post(
        headers: headers('tools/call'),
        json: body('tools/call', params: {'name': 'test/version'}),
      );
      expect(status, 400);
      expect(errorCode(text), -32020);
      // Messages name the headers in the casing the specification writes
      // them in, not the lower case dart:io looks them up by.
      expect(
        decode(text)['error'],
        containsPair('message', contains('Mcp-Name header is required')),
      );
    });

    test('requires an Mcp-Name header even without a body name', () async {
      // The header is required for the method, not merely mirrored when the
      // body happens to carry a value, so this never reaches the dispatcher.
      final (status, _, text) = await post(
        headers: headers('tools/call'),
        json: body('tools/call'),
      );
      expect(status, 400);
      expect(errorCode(text), -32020);
      expect(servers, isEmpty);
    });

    test('rejects a repeated Mcp-Method header', () async {
      final client = HttpClient();
      addTearDown(client.close);
      final request = await client.postUrl(uri);
      transportHeaders.forEach(request.headers.set);
      request.headers
        ..set('Mcp-Protocol-Version', version)
        ..add('Mcp-Method', 'tools/list')
        ..add('Mcp-Method', 'tools/list');
      request.write(jsonEncode(body('tools/list')));
      final response = await request.close();
      final text = await utf8.decodeStream(response);
      expect(response.statusCode, 400);
      expect(errorCode(text), -32020);
    });

    test('rejects a prompts/get without an Mcp-Name header', () async {
      final (status, _, text) = await post(
        headers: headers('prompts/get'),
        json: body('prompts/get', params: {'name': 'test/prompt'}),
      );
      expect(status, 400);
      expect(errorCode(text), -32020);
      expect(servers, isEmpty);
    });

    test('matches a prompts/get Mcp-Name against the name', () async {
      final (status, _, _) = await post(
        headers: {...headers('prompts/get'), 'Mcp-Name': 'test/prompt'},
        json: body('prompts/get', params: {'name': 'test/prompt'}),
      );
      // The method reaches the dispatcher, which supports no prompts.
      expect(status, 404);
    });

    test('decodes a base64 sentinel Mcp-Name header', () async {
      final encoded = base64.encode(utf8.encode('test/version'));
      final (status, _, _) = await post(
        headers: {...headers('tools/call'), 'Mcp-Name': '=?base64?$encoded?='},
        json: body('tools/call', params: {'name': 'test/version'}),
      );
      expect(status, 200);
    });

    test('rejects a base64 sentinel Mcp-Name for another tool', () async {
      final encoded = base64.encode(utf8.encode('test/throw'));
      final (status, _, text) = await post(
        headers: {...headers('tools/call'), 'Mcp-Name': '=?base64?$encoded?='},
        json: body('tools/call', params: {'name': 'test/version'}),
      );
      expect(status, 400);
      expect(errorCode(text), -32020);
      expect(servers, isEmpty);
    });

    test('rejects a repeated protocol version header', () async {
      final client = HttpClient();
      addTearDown(client.close);
      final request = await client.postUrl(uri);
      transportHeaders.forEach(request.headers.set);
      request.headers
        ..add('Mcp-Protocol-Version', version)
        ..add('Mcp-Protocol-Version', version)
        ..set('Mcp-Method', 'tools/list');
      request.write(jsonEncode(body('tools/list')));
      final response = await request.close();
      final text = await utf8.decodeStream(response);
      expect(response.statusCode, 400);
      expect(errorCode(text), -32020);
    });

    test('rejects an Mcp-Name sentinel that is not valid base64', () async {
      final (status, _, text) = await post(
        headers: {...headers('tools/call'), 'Mcp-Name': '=?base64?%%%?='},
        json: body('tools/call', params: {'name': 'test/version'}),
      );
      expect(status, 400);
      expect(errorCode(text), -32020);
    });

    test('rejects an overlapping base64 sentinel without hanging', () async {
      // '=?base64?=' is 10 characters: the prefix and suffix share a '?', so
      // a naive slice throws a RangeError the handler would never answer.
      final (status, _, text) = await post(
        headers: {...headers('tools/call'), 'Mcp-Name': '=?base64?='},
        json: body('tools/call', params: {'name': 'test/version'}),
      );
      expect(status, 400);
      expect(errorCode(text), -32020);
    });

    test('rejects a resources/read without an Mcp-Name header', () async {
      final (status, _, text) = await post(
        headers: headers('resources/read'),
        json: body('resources/read', params: {'uri': 'file:///doc.txt'}),
      );
      expect(status, 400);
      expect(errorCode(text), -32020);
      expect(servers, isEmpty);
    });

    test('matches a resources/read Mcp-Name against the uri', () async {
      final (status, _, _) = await post(
        headers: {...headers('resources/read'), 'Mcp-Name': 'file:///doc.txt'},
        json: body('resources/read', params: {'uri': 'file:///doc.txt'}),
      );
      // The method reaches the dispatcher, which has no such resource.
      expect(status, 404);
    });
  });

  group('removed 2025-11-25 mechanisms', () {
    test('ignores an Mcp-Session-Id header and mints none', () async {
      final (status, responseHeaders, text) = await post(
        headers: {...headers('tools/list'), 'Mcp-Session-Id': 'abc'},
        json: body('tools/list'),
      );
      expect(status, 200);
      expect(errorCode(text), isNull);
      expect(responseHeaders.value('Mcp-Session-Id'), isNull);
    });

    test('ignores a Last-Event-ID header', () async {
      final (status, _, text) = await post(
        headers: {...headers('tools/list'), 'Last-Event-ID': '42'},
        json: body('tools/list'),
      );
      expect(status, 200);
      expect(errorCode(text), isNull);
    });

    test('ignores an Mcp-Param header which contradicts the body', () async {
      // Nothing here opts into `x-mcp-header`, so `Mcp-Param-*` is a header
      // this handler does not recognize and RFC 9110 has it ignore it rather
      // than guess which parameter it mirrors.
      final (status, _, text) = await post(
        headers: {
          ...headers('tools/call'),
          'Mcp-Name': 'test/version',
          'Mcp-Param-Region': 'eu-west1',
        },
        json: body(
          'tools/call',
          params: {
            'name': 'test/version',
            'arguments': {'region': 'us-west1'},
          },
        ),
      );
      expect(status, 200);
      expect(errorCode(text), isNull);
    });
  });

  group('http methods', () {
    for (final method in ['GET', 'DELETE', 'PUT']) {
      test('rejects $method with 405', () async {
        final (status, responseHeaders, _) = await post(
          method: method,
          headers: method == 'DELETE' ? {'Mcp-Session-Id': 'abc'} : const {},
        );
        expect(status, 405);
        expect(responseHeaders.value(HttpHeaders.allowHeader), 'POST');
        expect(servers, isEmpty);
      });
    }
  });

  group('malformed bodies', () {
    test('rejects malformed JSON', () async {
      final (status, _, text) = await post(
        headers: transportHeaders,
        raw: '{"jsonrpc": "2.0",',
      );
      expect(status, 400);
      expect(errorCode(text), -32700);
    });

    test('rejects a batch array', () async {
      final (status, _, text) = await post(
        headers: transportHeaders,
        raw: jsonEncode([body('tools/list'), body('tools/list')]),
      );
      expect(status, 400);
      expect(errorCode(text), -32600);
      expect(decode(text)['error'], containsPair('message', contains('Batch')));
    });

    test('rejects an empty body', () async {
      final (status, _, text) = await post(headers: transportHeaders, raw: '');
      expect(status, 400);
      expect(errorCode(text), -32700);
    });

    test('rejects an explicit null request id', () async {
      final (status, _, text) = await post(
        headers: headers('tools/list'),
        json: {'jsonrpc': '2.0', 'id': null, 'method': 'tools/list'},
      );
      expect(status, 400);
      expect(errorCode(text), -32600);
    });
  });

  group('dispatch mappings', () {
    test('maps an unknown method to 404', () async {
      final (status, _, text) = await post(
        headers: headers('no/such/method'),
        json: body('no/such/method'),
      );
      expect(status, 404);
      expect(errorCode(text), -32601);
    });

    test('maps an initialize request from a modern client to 404', () async {
      final (status, _, text) = await post(
        headers: headers('initialize'),
        json: body('initialize'),
      );
      expect(status, 404);
      expect(errorCode(text), -32601);
      expect(servers, isEmpty);
    });

    test('maps an initialized notification carrying an id to 404', () async {
      // Without an id this is a notification and gets a 202; with one it is a
      // request for a method the request-scoped lifecycle does not have.
      final (status, _, text) = await post(
        headers: headers('notifications/initialized'),
        json: body('notifications/initialized'),
      );
      expect(status, 404);
      expect(errorCode(text), -32601);
      expect(servers, isEmpty);
    });

    test('answers a legacy client with the versions it supports', () async {
      // What a 2025-11-25 client actually sends: no `Mcp-Method` header and
      // no `_meta` envelope, both of which this revision introduced.
      final (status, _, text) = await post(
        headers: {...transportHeaders, 'Mcp-Protocol-Version': '2025-11-25'},
        json: {'jsonrpc': '2.0', 'id': 1, 'method': 'initialize'},
      );
      expect(status, 400);
      expect(errorCode(text), -32022);
      final data =
          (decode(text)['error'] as Map<String, Object?>)['data']
              as Map<String, Object?>;
      expect(data[Keys.supported], [version]);
      expect(servers, isEmpty);
    });

    test('keeps a tool error result as 200', () async {
      final (status, _, text) = await post(
        headers: {...headers('tools/call'), 'Mcp-Name': 'no/such/tool'},
        json: body('tools/call', params: {'name': 'no/such/tool'}),
      );
      expect(status, 200);
      final result = decode(text)['result'] as Map<String, Object?>;
      expect(result['isError'], isTrue);
    });

    test('keeps unmapped dispatcher errors as 200', () async {
      // A handler which throws something other than an RpcException surfaces
      // as an internal JSON-RPC error; only spec-mapped codes change the
      // HTTP status.
      final (status, _, text) = await post(
        headers: headers('test/crash'),
        json: body('test/crash'),
      );
      expect(status, 200);
      expect(errorCode(text), -32000);
    });

    test('maps an RpcException from a tool to its HTTP status', () async {
      final (status, _, text) = await post(
        headers: {...headers('tools/call'), 'Mcp-Name': 'test/throw'},
        json: body('tools/call', params: {'name': 'test/throw'}),
      );
      expect(status, 400);
      expect(errorCode(text), -32602);
    });

    test('maps a missing client capability error to 400', () async {
      final (status, _, text) = await post(
        headers: {...headers('tools/call'), 'Mcp-Name': 'test/needsSampling'},
        json: body('tools/call', params: {'name': 'test/needsSampling'}),
      );
      expect(status, 400);
      expect(errorCode(text), -32021);
    });

    test('rejects an envelope without client capabilities', () async {
      final request = body('tools/list');
      final params = request['params'] as Map<String, Object?>;
      final meta = params[Keys.meta] as Map<String, Object?>;
      meta.remove(Keys.clientCapabilitiesMeta);
      final (status, _, text) = await post(
        headers: headers('tools/list'),
        json: request,
      );
      expect(status, 400);
      expect(errorCode(text), -32602);
      expect(servers, isEmpty);
    });

    test('rejects a request without an envelope', () async {
      final (status, _, text) = await post(
        headers: headers('tools/list'),
        json: {'jsonrpc': '2.0', 'id': 1, 'method': 'tools/list'},
      );
      expect(status, 400);
      expect(errorCode(text), -32602);
      expect(servers, isEmpty);
    });

    test('rejects an unknown protocol version', () async {
      final (status, _, text) = await post(
        headers: headers('tools/list', headerVersion: '2099-01-01'),
        json: body('tools/list', bodyVersion: '2099-01-01'),
      );
      expect(status, 400);
      expect(errorCode(text), -32022);
      final data =
          (decode(text)['error'] as Map<String, Object?>)['data']
              as Map<String, Object?>;
      expect(data['requested'], '2099-01-01');
      expect(data['supported'], [version]);
      expect(servers, isEmpty);
    });

    test('rejects an earlier protocol version before the envelope', () async {
      // The envelope is itself a 2026-07-28 construct, so a client on an
      // earlier version cannot send one; the version answer has to come first
      // or that client never learns what to renegotiate to.
      final (status, _, text) = await post(
        headers: headers('tools/list', headerVersion: '2025-11-25'),
        json: {'jsonrpc': '2.0', 'id': 1, 'method': 'tools/list'},
      );
      expect(status, 400);
      expect(errorCode(text), -32022);
      final data =
          (decode(text)['error'] as Map<String, Object?>)['data']
              as Map<String, Object?>;
      expect(data['requested'], '2025-11-25');
      expect(data['supported'], [version]);
      expect(servers, isEmpty);
    });

    test('rejects a malformed client info', () async {
      final request = body('tools/list');
      final params = request['params'] as Map<String, Object?>;
      final meta = params[Keys.meta] as Map<String, Object?>;
      meta[Keys.clientInfoMeta] = 'test client';
      final (status, _, text) = await post(
        headers: headers('tools/list'),
        json: request,
      );
      expect(status, 400);
      expect(errorCode(text), -32602);
      expect(servers, isEmpty);
    });

    test('answers 500 when the server cannot be created', () async {
      final failing = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => failing.close(force: true));
      final failure = Completer<Object>();
      failing.listen(
        (request) => handleStreamableHttpRequest(
          request,
          (_) => throw StateError('no server today'),
        ).onError<Object>((error, _) => failure.complete(error)),
      );
      final client = HttpClient();
      addTearDown(client.close);
      final request = await client.postUrl(
        Uri.http('${failing.address.host}:${failing.port}', '/mcp'),
      );
      headers('tools/list').forEach(request.headers.set);
      request.write(jsonEncode(body('tools/list')));
      final response = await request.close();
      final text = await utf8.decodeStream(response);
      expect(response.statusCode, 500);
      expect(errorCode(text), -32603);
      expect(await failure.future, isStateError);
    });
  });

  group('request isolation', () {
    String probed(String text) =>
        (((decode(text)['result'] as Map<String, Object?>)['content'] as List)
                    .single
                as Map<String, Object?>)['text']
            as String;

    test('gives every request a fresh server and context', () async {
      final probeHeaders = {
        ...headers('tools/call'),
        'Mcp-Name': 'test/capabilities',
      };
      final probeBody = {'name': 'test/capabilities'};
      final (_, _, first) = await post(
        headers: probeHeaders,
        json: body(
          'tools/call',
          params: probeBody,
          capabilities: {'sampling': <String, Object?>{}},
        ),
      );
      final (_, _, second) = await post(
        headers: probeHeaders,
        json: body('tools/call', params: probeBody),
      );
      expect(probed(first), 'true');
      expect(probed(second), 'false');
      expect(servers, hasLength(2));
      expect(servers[0], isNot(same(servers[1])));
    });

    test('gives concurrent requests independent contexts', () async {
      final probeHeaders = {
        ...headers('tools/call'),
        'Mcp-Name': 'test/capabilities',
      };
      final probeBody = {'name': 'test/capabilities'};
      final withSampling = post(
        headers: probeHeaders,
        json: body(
          'tools/call',
          params: probeBody,
          capabilities: {'sampling': <String, Object?>{}},
        ),
      );
      final without = post(
        headers: probeHeaders,
        json: body('tools/call', params: probeBody),
      );
      final [(_, _, first), (_, _, second)] = await Future.wait([
        withSampling,
        without,
      ]);
      expect(probed(first), 'true');
      expect(probed(second), 'false');
      expect(servers, hasLength(2));
    });

    test('accepts an optional client info', () async {
      final request = body('tools/list');
      final params = request['params'] as Map<String, Object?>;
      final meta = params[Keys.meta] as Map<String, Object?>;
      meta[Keys.clientInfoMeta] = {'name': 'test client', 'version': '1.0.0'};
      final (status, _, text) = await post(
        headers: headers('tools/list'),
        json: request,
      );
      expect(status, 200);
      expect(errorCode(text), isNull);
    });

    test('passes server notifications to the handler', () async {
      final (status, _, text) = await post(
        headers: {...headers('tools/call'), 'Mcp-Name': 'test/notify'},
        json: body('tools/call', params: {'name': 'test/notify'}),
      );
      expect(status, 200);
      expect(errorCode(text), isNull);
      expect(notifications, hasLength(1));
      expect(
        notifications.single['method'],
        LoggingMessageNotification.methodName,
      );
    });
  });
}

base class _HttpTestServer extends MCPServer with ToolsSupport {
  bool get _declaredSampling => clientCapabilities.sampling != null;

  _HttpTestServer(super.channel)
    : super.fromStreamChannel(
        implementation: Implementation(
          name: 'http test server',
          version: '0.1.0',
        ),
      ) {
    registerTool(
      Tool(name: 'test/version', inputSchema: ObjectSchema()),
      (_) => CallToolResult(content: [TextContent(text: '1.2.3')]),
    );
    registerTool(
      Tool(name: 'test/throw', inputSchema: ObjectSchema()),
      (_) => throw RpcException.invalidParams('This tool always throws'),
    );
    registerRequestHandler<Request?, Result?>(
      'test/crash',
      (_) => throw StateError('This handler always crashes'),
    );
    registerTool(
      Tool(name: 'test/capabilities', inputSchema: ObjectSchema()),
      (_) => CallToolResult(content: [TextContent(text: '$_declaredSampling')]),
    );
    registerTool(
      Tool(name: 'test/needsSampling', inputSchema: ObjectSchema()),
      (_) =>
          throw RpcException(
            McpErrorCodes.missingRequiredClientCapability,
            'This tool needs the sampling capability',
          ),
    );
    registerTool(Tool(name: 'test/notify', inputSchema: ObjectSchema()), (_) {
      sendNotification(
        LoggingMessageNotification.methodName,
        LoggingMessageNotification(
          level: LoggingLevel.error,
          data: 'from tool',
        ),
      );
      return CallToolResult(content: [TextContent(text: 'notified')]);
    });
  }
}
