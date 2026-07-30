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
import 'package:json_rpc_2/error_code.dart' as error_code;
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:test/test.dart';

/// The protocol version this transport speaks.
const version = '2026-07-28';

/// Shorthands for the method names these tests post, so that a name reads as
/// one token at the call site.
///
/// The two notifications keep their kind in the name because several tests
/// turn on whether a body is a request or a notification.
const listTools = ListToolsRequest.methodName;
const callTool = CallToolRequest.methodName;
const getPrompt = GetPromptRequest.methodName;
const readResource = ReadResourceRequest.methodName;
const initialize = InitializeRequest.methodName;
const initializedNotification = InitializedNotification.methodName;
const progressNotification = ProgressNotification.methodName;

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
    Keys.jsonrpc: '2.0',
    if (id != null) Keys.id: id,
    Keys.method: method,
    Keys.params: {
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
      (decode(text)[Keys.error] as Map<String, Object?>?)?[Keys.code];

  /// Sends [payload] over a raw socket and returns the raw response text.
  ///
  /// [HttpClient] refuses to send the malformed header values some tests
  /// probe with and folds repeated header lines into one, so those requests
  /// have to go over a socket. The payload must ask for `Connection: close`
  /// or the read below never finishes.
  Future<String> rawRequest(String payload) async {
    final socket = await Socket.connect(httpServer.address, httpServer.port);
    socket.write(payload);
    await socket.flush();
    final response = utf8.decode(
      await socket.fold(<int>[], (bytes, chunk) => bytes..addAll(chunk)),
    );
    socket.destroy();
    return response;
  }

  /// The JSON body of a raw response, cut out of its framing.
  String jsonBody(String response) =>
      response.substring(response.indexOf('{'), response.lastIndexOf('}') + 1);

  group('happy path', () {
    test('answers tools/list with JSON and server info', () async {
      final (status, responseHeaders, text) = await post(
        headers: headers(listTools),
        json: body(listTools),
      );
      expect(status, 200);
      expect(responseHeaders.contentType?.mimeType, 'application/json');
      expect(responseHeaders.contentType?.charset, 'utf-8');
      expect(responseHeaders.value('Mcp-Session-Id'), isNull);
      final response = decode(text);
      expect(response[Keys.id], 1);
      final result = response[Keys.result] as Map<String, Object?>;
      final tools = result[Keys.tools] as List;
      expect(
        tools.map((tool) => (tool as Map<String, Object?>)[Keys.name]),
        contains('test/version'),
      );
      expect(
        (result[Keys.meta] as Map<String, Object?>)[Keys.serverInfoMeta],
        isNotNull,
      );
    });

    test('answers tools/call with the tool result', () async {
      final (status, _, text) = await post(
        headers: {...headers(callTool), 'Mcp-Name': 'test/version'},
        json: body(callTool, params: {Keys.name: 'test/version'}),
      );
      expect(status, 200);
      final result = decode(text)[Keys.result] as Map<String, Object?>;
      final content = result[Keys.content] as List;
      expect((content.single as Map<String, Object?>)[Keys.text], '1.2.3');
    });
  });

  group('notifications and responses', () {
    test('acknowledges a notification without headers or dispatch', () async {
      final (status, _, text) = await post(
        headers: transportHeaders,
        json: {Keys.jsonrpc: '2.0', Keys.method: progressNotification},
      );
      expect(status, 202);
      expect(text, isEmpty);
      expect(servers, isEmpty);
    });

    test('acknowledges an unknown notification', () async {
      final (status, _, text) = await post(
        headers: headers('no/such/notification'),
        json: {Keys.jsonrpc: '2.0', Keys.method: 'no/such/notification'},
      );
      expect(status, 202);
      expect(text, isEmpty);
      expect(servers, isEmpty);
    });

    test('rejects a JSON-RPC response body', () async {
      final (status, _, text) = await post(
        headers: transportHeaders,
        json: {
          Keys.jsonrpc: '2.0',
          Keys.id: 1,
          Keys.result: <String, Object?>{},
        },
      );
      expect(status, 400);
      expect(errorCode(text), error_code.INVALID_REQUEST);
      expect(servers, isEmpty);
    });

    test('rejects a message without a method before acknowledging', () async {
      // A body with neither an id nor a method is a notification by shape,
      // but the missing method is caught first, so it is a 400 not a 202.
      final (status, _, text) = await post(
        headers: transportHeaders,
        json: {Keys.jsonrpc: '2.0'},
      );
      expect(status, 400);
      expect(errorCode(text), error_code.INVALID_REQUEST);
      expect(servers, isEmpty);
    });

    test('rejects a non-string method', () async {
      final (status, _, text) = await post(
        headers: transportHeaders,
        json: {Keys.jsonrpc: '2.0', Keys.id: 1, Keys.method: 42},
      );
      expect(status, 400);
      expect(errorCode(text), error_code.INVALID_REQUEST);
    });

    test('rejects a scalar body', () async {
      final (status, _, text) = await post(
        headers: transportHeaders,
        raw: '42',
      );
      expect(status, 400);
      expect(errorCode(text), error_code.INVALID_REQUEST);
    });
  });

  group('content negotiation', () {
    test('rejects a request without a Content-Type header', () async {
      final (status, _, text) = await post(
        headers: {
          'Accept': 'application/json, text/event-stream',
          'Mcp-Protocol-Version': version,
          'Mcp-Method': listTools,
        },
        json: body(listTools),
      );
      expect(status, 400);
      expect(errorCode(text), McpErrorCodes.headerMismatch);
      expect(servers, isEmpty);
    });

    test('rejects a text/plain Content-Type', () async {
      final (status, responseHeaders, text) = await post(
        headers: {...headers(listTools), 'Content-Type': 'text/plain'},
        json: body(listTools),
      );
      expect(status, 400);
      expect(responseHeaders.contentType?.mimeType, 'application/json');
      expect(errorCode(text), McpErrorCodes.headerMismatch);
    });

    test('tolerates a charset on the Content-Type', () async {
      final (status, _, text) = await post(
        headers: {
          ...headers(listTools),
          'Content-Type': 'application/json; charset=utf-8',
        },
        json: body(listTools),
      );
      expect(status, 200);
      expect(errorCode(text), isNull);
    });

    test('rejects a request without an Accept header', () async {
      final (status, _, text) = await post(
        headers: {
          'Content-Type': 'application/json',
          'Mcp-Protocol-Version': version,
          'Mcp-Method': listTools,
        },
        json: body(listTools),
      );
      expect(status, 400);
      expect(errorCode(text), McpErrorCodes.headerMismatch);
      expect(servers, isEmpty);
    });

    test('rejects an Accept header without text/event-stream', () async {
      final (status, responseHeaders, text) = await post(
        headers: {...headers(listTools), 'Accept': 'application/json'},
        json: body(listTools),
      );
      expect(status, 400);
      expect(responseHeaders.contentType?.mimeType, 'application/json');
      expect(errorCode(text), McpErrorCodes.headerMismatch);
    });

    test('rejects an Accept header without application/json', () async {
      final (status, _, text) = await post(
        headers: {...headers(listTools), 'Accept': 'text/event-stream'},
        json: body(listTools),
      );
      expect(status, 400);
      expect(errorCode(text), McpErrorCodes.headerMismatch);
    });

    test('accepts the */* wildcard', () async {
      final (status, _, text) = await post(
        headers: {...headers(listTools), 'Accept': '*/*'},
        json: body(listTools),
      );
      expect(status, 200);
      expect(errorCode(text), isNull);
    });

    test('accepts type wildcards with quality values', () async {
      final (status, _, text) = await post(
        headers: {
          ...headers(listTools),
          'Accept': 'application/*;q=0.9, text/*;q=0.8',
        },
        json: body(listTools),
      );
      expect(status, 200);
      expect(errorCode(text), isNull);
    });

    test('rejects a Content-Type dart:io cannot parse', () async {
      // dart:io parses the header lazily and throws when it is first read,
      // and that throw must land as a 400, not escape the handler and leave
      // the request unanswered.
      final requestBody = jsonEncode(body(listTools));
      final response = await rawRequest(
        'POST /mcp HTTP/1.1\r\n'
        'Host: localhost\r\n'
        'Content-Type: application/json; charset="utf-8\r\n'
        'Accept: application/json, text/event-stream\r\n'
        'Content-Length: ${requestBody.length}\r\n'
        'Connection: close\r\n'
        '\r\n'
        '$requestBody',
      );
      expect(response, startsWith('HTTP/1.1 400'));
      expect(errorCode(jsonBody(response)), McpErrorCodes.headerMismatch);
      expect(servers, isEmpty);
    });

    test('acknowledges a notification which accepts nothing', () async {
      // The Accept rule only applies to requests, which are the only messages
      // that get a body back.
      final (status, _, text) = await post(
        headers: {'Content-Type': 'application/json'},
        json: {Keys.jsonrpc: '2.0', Keys.method: progressNotification},
      );
      expect(status, 202);
      expect(text, isEmpty);
    });
  });

  group('required headers', () {
    test('rejects a missing protocol version header', () async {
      final (status, _, text) = await post(
        headers: {...transportHeaders, 'Mcp-Method': listTools},
        json: body(listTools),
      );
      expect(status, 400);
      expect(errorCode(text), McpErrorCodes.headerMismatch);
    });

    test('rejects a header and body version mismatch', () async {
      final (status, _, text) = await post(
        headers: headers(listTools),
        json: body(listTools, bodyVersion: '2025-06-18'),
      );
      expect(status, 400);
      expect(errorCode(text), McpErrorCodes.headerMismatch);
    });

    test('rejects a missing Mcp-Method header', () async {
      final (status, _, text) = await post(
        headers: {...transportHeaders, 'Mcp-Protocol-Version': version},
        json: body(listTools),
      );
      expect(status, 400);
      expect(errorCode(text), McpErrorCodes.headerMismatch);
    });

    test('rejects an Mcp-Method header mismatch', () async {
      final (status, _, text) = await post(
        headers: headers(callTool),
        json: body(listTools),
      );
      expect(status, 400);
      expect(errorCode(text), McpErrorCodes.headerMismatch);
      expect(servers, isEmpty);
    });

    test('compares Mcp-Method values case sensitively', () async {
      // Header names are case insensitive, header values are not.
      final (status, _, text) = await post(
        headers: {
          ...headers(callTool, headerMethod: 'Tools/Call'),
          'Mcp-Name': 'test/version',
        },
        json: body(callTool, params: {Keys.name: 'test/version'}),
      );
      expect(status, 400);
      expect(errorCode(text), McpErrorCodes.headerMismatch);
      expect(servers, isEmpty);
    });

    test('rejects a tools/call without an Mcp-Name header', () async {
      final (status, _, text) = await post(
        headers: headers(callTool),
        json: body(callTool, params: {Keys.name: 'test/version'}),
      );
      expect(status, 400);
      expect(errorCode(text), McpErrorCodes.headerMismatch);
      // Messages name the headers in the casing the specification writes
      // them in, not the lower case dart:io looks them up by.
      expect(
        decode(text)[Keys.error],
        containsPair(Keys.message, contains('Mcp-Name header is required')),
      );
    });

    test('requires an Mcp-Name header even without a body name', () async {
      // The header is required for the method, not merely mirrored when the
      // body happens to carry a value, so this never reaches the dispatcher.
      final (status, _, text) = await post(
        headers: headers(callTool),
        json: body(callTool),
      );
      expect(status, 400);
      expect(errorCode(text), McpErrorCodes.headerMismatch);
      expect(servers, isEmpty);
    });

    test('rejects a repeated Mcp-Method header', () async {
      final client = HttpClient();
      addTearDown(client.close);
      final request = await client.postUrl(uri);
      transportHeaders.forEach(request.headers.set);
      request.headers
        ..set('Mcp-Protocol-Version', version)
        ..add('Mcp-Method', listTools)
        ..add('Mcp-Method', listTools);
      request.write(jsonEncode(body(listTools)));
      final response = await request.close();
      final text = await utf8.decodeStream(response);
      expect(response.statusCode, 400);
      expect(errorCode(text), McpErrorCodes.headerMismatch);
    });

    test('rejects a prompts/get without an Mcp-Name header', () async {
      final (status, _, text) = await post(
        headers: headers(getPrompt),
        json: body(getPrompt, params: {Keys.name: 'test/prompt'}),
      );
      expect(status, 400);
      expect(errorCode(text), McpErrorCodes.headerMismatch);
      expect(servers, isEmpty);
    });

    test('matches a prompts/get Mcp-Name against the name', () async {
      final (status, _, _) = await post(
        headers: {...headers(getPrompt), 'Mcp-Name': 'test/prompt'},
        json: body(getPrompt, params: {Keys.name: 'test/prompt'}),
      );
      // The method reaches the dispatcher, which supports no prompts.
      expect(status, 404);
    });

    test('decodes a base64 sentinel Mcp-Name header', () async {
      final encoded = base64.encode(utf8.encode('test/version'));
      final (status, _, _) = await post(
        headers: {...headers(callTool), 'Mcp-Name': '=?base64?$encoded?='},
        json: body(callTool, params: {Keys.name: 'test/version'}),
      );
      expect(status, 200);
    });

    test('rejects a base64 sentinel Mcp-Name for another tool', () async {
      final encoded = base64.encode(utf8.encode('test/throw'));
      final (status, _, text) = await post(
        headers: {...headers(callTool), 'Mcp-Name': '=?base64?$encoded?='},
        json: body(callTool, params: {Keys.name: 'test/version'}),
      );
      expect(status, 400);
      expect(errorCode(text), McpErrorCodes.headerMismatch);
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
        ..set('Mcp-Method', listTools);
      request.write(jsonEncode(body(listTools)));
      final response = await request.close();
      final text = await utf8.decodeStream(response);
      expect(response.statusCode, 400);
      expect(errorCode(text), McpErrorCodes.headerMismatch);
    });

    test('rejects an Mcp-Name sentinel that is not valid base64', () async {
      final (status, _, text) = await post(
        headers: {...headers(callTool), 'Mcp-Name': '=?base64?%%%?='},
        json: body(callTool, params: {Keys.name: 'test/version'}),
      );
      expect(status, 400);
      expect(errorCode(text), McpErrorCodes.headerMismatch);
    });

    test('rejects an overlapping base64 sentinel without hanging', () async {
      // '=?base64?=' is 10 characters: the prefix and suffix share a '?', so
      // a naive slice throws a RangeError the handler would never answer.
      final (status, _, text) = await post(
        headers: {...headers(callTool), 'Mcp-Name': '=?base64?='},
        json: body(callTool, params: {Keys.name: 'test/version'}),
      );
      expect(status, 400);
      expect(errorCode(text), McpErrorCodes.headerMismatch);
    });

    test('rejects a resources/read without an Mcp-Name header', () async {
      final (status, _, text) = await post(
        headers: headers(readResource),
        json: body(readResource, params: {Keys.uri: 'file:///doc.txt'}),
      );
      expect(status, 400);
      expect(errorCode(text), McpErrorCodes.headerMismatch);
      expect(servers, isEmpty);
    });

    test('matches a resources/read Mcp-Name against the uri', () async {
      final (status, _, _) = await post(
        headers: {...headers(readResource), 'Mcp-Name': 'file:///doc.txt'},
        json: body(readResource, params: {Keys.uri: 'file:///doc.txt'}),
      );
      // The method reaches the dispatcher, which has no such resource.
      expect(status, 404);
    });
  });

  group('removed 2025-11-25 mechanisms', () {
    test('ignores an Mcp-Session-Id header and mints none', () async {
      final (status, responseHeaders, text) = await post(
        headers: {...headers(listTools), 'Mcp-Session-Id': 'abc'},
        json: body(listTools),
      );
      expect(status, 200);
      expect(errorCode(text), isNull);
      expect(responseHeaders.value('Mcp-Session-Id'), isNull);
    });

    test('ignores a Last-Event-ID header', () async {
      final (status, _, text) = await post(
        headers: {...headers(listTools), 'Last-Event-ID': '42'},
        json: body(listTools),
      );
      expect(status, 200);
      expect(errorCode(text), isNull);
    });

    test('ignores an Mcp-Param header which contradicts the body', () async {
      // Nothing here opts into `x-mcp-header`, so `Mcp-Param-*` is a header
      // this handler does not recognize, and it is ignored rather than
      // guessed at.
      final (status, _, text) = await post(
        headers: {
          ...headers(callTool),
          'Mcp-Name': 'test/version',
          'Mcp-Param-Region': 'eu-west1',
        },
        json: body(
          callTool,
          params: {
            Keys.name: 'test/version',
            Keys.arguments: {'region': 'us-west1'},
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

  group('client disconnects', () {
    /// Sends a POST whose body never finishes arriving, then hangs up.
    Future<void> disconnectMidBody({required String contentType}) async {
      final socket = await Socket.connect(httpServer.address, httpServer.port);
      socket.write(
        'POST /mcp HTTP/1.1\r\n'
        'Host: localhost\r\n'
        'Content-Type: $contentType\r\n'
        'Accept: application/json, text/event-stream\r\n'
        'Content-Length: 500\r\n'
        '\r\n'
        '{"jsonrpc":"2.0",',
      );
      await socket.flush();
      socket.destroy();
      // The handler sees the disconnect asynchronously; give the event loop
      // a beat so a failure surfaces inside this test.
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    test('survives a disconnect while reading the body', () async {
      await disconnectMidBody(contentType: 'application/json');
      // There is no response to assert on, so the proof that the handler
      // survived is a request which round-trips after the disconnect.
      final (status, _, text) = await post(
        headers: headers(listTools),
        json: body(listTools),
      );
      expect(status, 200);
      expect(errorCode(text), isNull);
    });

    test('survives a disconnect while draining a rejected body', () async {
      await disconnectMidBody(contentType: 'text/plain');
      final (status, _, text) = await post(
        headers: headers(listTools),
        json: body(listTools),
      );
      expect(status, 200);
      expect(errorCode(text), isNull);
    });
  });

  group('malformed bodies', () {
    test('rejects malformed JSON', () async {
      final (status, _, text) = await post(
        headers: transportHeaders,
        raw: '{"jsonrpc": "2.0",',
      );
      expect(status, 400);
      expect(errorCode(text), error_code.PARSE_ERROR);
    });

    test('rejects a batch array', () async {
      final (status, _, text) = await post(
        headers: transportHeaders,
        raw: jsonEncode([body(listTools), body(listTools)]),
      );
      expect(status, 400);
      expect(errorCode(text), error_code.INVALID_REQUEST);
      expect(
        decode(text)[Keys.error],
        containsPair(Keys.message, contains('Batch')),
      );
    });

    test('rejects an empty body', () async {
      final (status, _, text) = await post(headers: transportHeaders, raw: '');
      expect(status, 400);
      expect(errorCode(text), error_code.PARSE_ERROR);
    });

    test('rejects an explicit null request id', () async {
      final (status, _, text) = await post(
        headers: headers(listTools),
        json: {Keys.jsonrpc: '2.0', Keys.id: null, Keys.method: listTools},
      );
      expect(status, 400);
      expect(errorCode(text), error_code.INVALID_REQUEST);
    });
  });

  group('rejection bodies', () {
    Map<String, Object?> errorData(String text) =>
        (decode(text)[Keys.error] as Map<String, Object?>)[Keys.data]
            as Map<String, Object?>;

    test('echo the message when the exception carries no data', () async {
      // `RpcException.serialize` injects the request into `error.data` when
      // the exception has no data of its own.
      final request = body(listTools);
      final (status, _, text) = await post(
        headers: headers(callTool),
        json: request,
      );
      expect(status, 400);
      expect(errorData(text)[Keys.request], request);
    });

    test('echo the message alongside data the exception carries', () async {
      // ...and injects it next to existing data when that is a map without
      // a `request` key, so the version payload keeps its echo too.
      final request = {Keys.jsonrpc: '2.0', Keys.id: 1, Keys.method: listTools};
      final (status, _, text) = await post(
        headers: {...transportHeaders, 'Mcp-Protocol-Version': '2025-11-25'},
        json: request,
      );
      expect(status, 400);
      final data = errorData(text);
      expect(data[Keys.supported], [version]);
      expect(data[Keys.request], request);
    });

    test('echo raw text for unparsed bodies, null for unread ones', () async {
      final (_, _, unparsed) = await post(
        headers: transportHeaders,
        raw: '{"jsonrpc": "2.0",',
      );
      expect(errorData(unparsed)[Keys.request], '{"jsonrpc": "2.0",');

      final (_, _, unread) = await post(
        headers: {...headers(listTools), 'Content-Type': 'text/plain'},
        json: body(listTools),
      );
      final data = errorData(unread);
      expect(data.containsKey(Keys.request), true);
      expect(data[Keys.request], isNull);
    });
  });

  group('dispatch mappings', () {
    test('maps an unknown method to 404', () async {
      final (status, _, text) = await post(
        headers: headers('no/such/method'),
        json: body('no/such/method'),
      );
      expect(status, 404);
      expect(errorCode(text), error_code.METHOD_NOT_FOUND);
    });

    test('maps an initialize request from a modern client to 404', () async {
      final (status, _, text) = await post(
        headers: headers(initialize),
        json: body(initialize),
      );
      expect(status, 404);
      expect(errorCode(text), error_code.METHOD_NOT_FOUND);
      expect(servers, isEmpty);
    });

    test('maps an initialized notification carrying an id to 404', () async {
      // Without an id this is a notification and gets a 202; with one it is a
      // request for a method the request-scoped lifecycle does not have.
      final (status, _, text) = await post(
        headers: headers(initializedNotification),
        json: body(initializedNotification),
      );
      expect(status, 404);
      expect(errorCode(text), error_code.METHOD_NOT_FOUND);
      expect(servers, isEmpty);
    });

    test('answers a legacy client with the versions it supports', () async {
      // What a 2025-11-25 client actually sends: no `Mcp-Method` header and
      // no `_meta` envelope, both of which this revision introduced.
      final (status, _, text) = await post(
        headers: {...transportHeaders, 'Mcp-Protocol-Version': '2025-11-25'},
        json: {Keys.jsonrpc: '2.0', Keys.id: 1, Keys.method: initialize},
      );
      expect(status, 400);
      expect(errorCode(text), McpErrorCodes.unsupportedProtocolVersion);
      final data =
          (decode(text)[Keys.error] as Map<String, Object?>)[Keys.data]
              as Map<String, Object?>;
      expect(data[Keys.supported], [version]);
      expect(servers, isEmpty);
    });

    test('keeps a tool error result as 200', () async {
      final (status, _, text) = await post(
        headers: {...headers(callTool), 'Mcp-Name': 'no/such/tool'},
        json: body(callTool, params: {Keys.name: 'no/such/tool'}),
      );
      expect(status, 200);
      final result = decode(text)[Keys.result] as Map<String, Object?>;
      expect(result[Keys.isError], isTrue);
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
      expect(errorCode(text), error_code.SERVER_ERROR);
    });

    test('maps an RpcException from a tool to its HTTP status', () async {
      final (status, _, text) = await post(
        headers: {...headers(callTool), 'Mcp-Name': 'test/throw'},
        json: body(callTool, params: {Keys.name: 'test/throw'}),
      );
      expect(status, 400);
      expect(errorCode(text), error_code.INVALID_PARAMS);
    });

    test('maps a missing client capability error to 400', () async {
      final (status, _, text) = await post(
        headers: {...headers(callTool), 'Mcp-Name': 'test/needsSampling'},
        json: body(callTool, params: {Keys.name: 'test/needsSampling'}),
      );
      expect(status, 400);
      expect(errorCode(text), McpErrorCodes.missingRequiredClientCapability);
    });

    test('rejects an envelope without client capabilities', () async {
      final request = body(listTools);
      final params = request[Keys.params] as Map<String, Object?>;
      final meta = params[Keys.meta] as Map<String, Object?>;
      meta.remove(Keys.clientCapabilitiesMeta);
      final (status, _, text) = await post(
        headers: headers(listTools),
        json: request,
      );
      expect(status, 400);
      expect(errorCode(text), error_code.INVALID_PARAMS);
      expect(servers, isEmpty);
    });

    test('rejects a request without an envelope', () async {
      final (status, _, text) = await post(
        headers: headers(listTools),
        json: {Keys.jsonrpc: '2.0', Keys.id: 1, Keys.method: listTools},
      );
      expect(status, 400);
      expect(errorCode(text), error_code.INVALID_PARAMS);
      expect(servers, isEmpty);
    });

    test('rejects an unknown protocol version', () async {
      final (status, _, text) = await post(
        headers: headers(listTools, headerVersion: '2099-01-01'),
        json: body(listTools, bodyVersion: '2099-01-01'),
      );
      expect(status, 400);
      expect(errorCode(text), McpErrorCodes.unsupportedProtocolVersion);
      final data =
          (decode(text)[Keys.error] as Map<String, Object?>)[Keys.data]
              as Map<String, Object?>;
      expect(data[Keys.requested], '2099-01-01');
      expect(data[Keys.supported], [version]);
      expect(servers, isEmpty);
    });

    test('rejects an earlier protocol version before the envelope', () async {
      // The envelope is itself a 2026-07-28 construct, so a client on an
      // earlier version cannot send one; the version answer has to come first
      // or that client never learns what to renegotiate to.
      final (status, _, text) = await post(
        headers: headers(listTools, headerVersion: '2025-11-25'),
        json: {Keys.jsonrpc: '2.0', Keys.id: 1, Keys.method: listTools},
      );
      expect(status, 400);
      expect(errorCode(text), McpErrorCodes.unsupportedProtocolVersion);
      final data =
          (decode(text)[Keys.error] as Map<String, Object?>)[Keys.data]
              as Map<String, Object?>;
      expect(data[Keys.requested], '2025-11-25');
      expect(data[Keys.supported], [version]);
      expect(servers, isEmpty);
    });

    test('rejects a malformed client info', () async {
      final request = body(listTools);
      final params = request[Keys.params] as Map<String, Object?>;
      final meta = params[Keys.meta] as Map<String, Object?>;
      meta[Keys.clientInfoMeta] = 'test client';
      final (status, _, text) = await post(
        headers: headers(listTools),
        json: request,
      );
      expect(status, 400);
      expect(errorCode(text), error_code.INVALID_PARAMS);
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
      headers(listTools).forEach(request.headers.set);
      request.write(jsonEncode(body(listTools)));
      final response = await request.close();
      final text = await utf8.decodeStream(response);
      expect(response.statusCode, 500);
      expect(errorCode(text), error_code.INTERNAL_ERROR);
      expect(await failure.future, isStateError);
    });
  });

  group('request isolation', () {
    String probed(String text) =>
        (((decode(text)[Keys.result] as Map<String, Object?>)[Keys.content]
                        as List)
                    .single
                as Map<String, Object?>)[Keys.text]
            as String;

    test('gives every request a fresh server and context', () async {
      final probeHeaders = {
        ...headers(callTool),
        'Mcp-Name': 'test/capabilities',
      };
      final probeBody = {Keys.name: 'test/capabilities'};
      final (_, _, first) = await post(
        headers: probeHeaders,
        json: body(
          callTool,
          params: probeBody,
          capabilities: {Keys.sampling: <String, Object?>{}},
        ),
      );
      final (_, _, second) = await post(
        headers: probeHeaders,
        json: body(callTool, params: probeBody),
      );
      expect(probed(first), 'true');
      expect(probed(second), 'false');
      expect(servers, hasLength(2));
      expect(servers[0], isNot(same(servers[1])));
    });

    test('gives concurrent requests independent contexts', () async {
      final probeHeaders = {
        ...headers(callTool),
        'Mcp-Name': 'test/capabilities',
      };
      final probeBody = {Keys.name: 'test/capabilities'};
      final withSampling = post(
        headers: probeHeaders,
        json: body(
          callTool,
          params: probeBody,
          capabilities: {Keys.sampling: <String, Object?>{}},
        ),
      );
      final without = post(
        headers: probeHeaders,
        json: body(callTool, params: probeBody),
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
      final request = body(listTools);
      final params = request[Keys.params] as Map<String, Object?>;
      final meta = params[Keys.meta] as Map<String, Object?>;
      meta[Keys.clientInfoMeta] = {
        Keys.name: 'test client',
        Keys.version: '1.0.0',
      };
      final (status, _, text) = await post(
        headers: headers(listTools),
        json: request,
      );
      expect(status, 200);
      expect(errorCode(text), isNull);
    });

    test('passes server notifications to the handler', () async {
      final (status, _, text) = await post(
        headers: {...headers(callTool), 'Mcp-Name': 'test/notify'},
        json: body(callTool, params: {Keys.name: 'test/notify'}),
      );
      expect(status, 200);
      expect(errorCode(text), isNull);
      expect(notifications, hasLength(1));
      expect(
        notifications.single[Keys.method],
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
