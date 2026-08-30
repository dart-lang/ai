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
/// The notifications keep their kind in the name because several tests turn
/// on whether a body is a request or a notification.
const listTools = ListToolsRequest.methodName;
const callTool = CallToolRequest.methodName;
const getPrompt = GetPromptRequest.methodName;
const readResource = ReadResourceRequest.methodName;
const initialize = InitializeRequest.methodName;
const initializedNotification = InitializedNotification.methodName;
const progressNotification = ProgressNotification.methodName;
const ping = PingRequest.methodName;
const setLevel = SetLevelRequest.methodName;
const subscribe = SubscribeRequest.methodName;
const unsubscribe = UnsubscribeRequest.methodName;
const rootsListChangedNotification = RootsListChangedNotification.methodName;

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

  /// The field lines of one SSE frame, keyed by field name.
  Map<String, String> fields(String frame) {
    final fields = <String, String>{};
    for (final line in frame.split('\n')) {
      final colon = line.indexOf(':');
      if (colon > 0) {
        fields[line.substring(0, colon)] = line.substring(colon + 1).trim();
      }
    }
    return fields;
  }

  /// The frames an SSE response [text] carries.
  ///
  /// Reads the fields the way a client does instead of matching the bytes the
  /// transport writes, which lets a change to the framing fail a test here.
  List<Map<String, String>> frames(String text) => [
    for (final frame in text.split('\n\n'))
      if (frame.trim().isNotEmpty) fields(frame),
  ];

  /// The JSON-RPC messages an SSE response [text] carries, in order.
  List<Map<String, Object?>> events(String text) => [
    for (final frame in frames(text))
      jsonDecode(frame['data']!) as Map<String, Object?>,
  ];

  Object? errorCode(String text) =>
      (decode(text)[Keys.error] as Map<String, Object?>?)?[Keys.code];

  Object? errorMessage(String text) =>
      (decode(text)[Keys.error] as Map<String, Object?>?)?[Keys.message];

  /// Sends [payload] over a raw socket and returns the raw response text.
  ///
  /// [HttpClient] refuses to send the malformed header values some tests
  /// probe with and folds repeated header lines into one, so those requests
  /// have to go over a socket. The payload must ask for `Connection: close`
  /// or the read below never finishes.
  Future<String> rawRequest(
    String payload, [
    List<int> bodyBytes = const [],
  ]) async {
    final socket = await Socket.connect(httpServer.address, httpServer.port);
    socket.add(latin1.encode(payload));
    socket.add(bodyBytes);
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

  group('client channel', () {
    test('posts request metadata and emits the JSON response', () async {
      final wireServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => wireServer.close(force: true));
      final observed = Completer<void>();
      wireServer.listen((request) async {
        try {
          final sent =
              jsonDecode(await utf8.decodeStream(request))
                  as Map<String, Object?>;
          expect(request.method, 'POST');
          expect(request.headers.contentType?.mimeType, 'application/json');
          expect(
            request.headers.value(HttpHeaders.acceptHeader),
            'application/json, text/event-stream',
          );
          expect(request.headers.value('MCP-Protocol-Version'), version);
          expect(request.headers.value('Mcp-Method'), 'tools/call');
          expect(request.headers.value('Mcp-Name'), '=?base64?IGNhZsOpIA==?=');

          final params = sent[Keys.params] as Map<String, Object?>;
          expect(params[Keys.arguments], {'value': 1});
          final meta = params[Keys.meta] as Map<String, Object?>;
          expect(meta['com.example/keep'], true);
          expect(meta[Keys.protocolVersionMeta], version);
          expect(meta[Keys.clientCapabilitiesMeta], {
            'sampling': <String, Object?>{},
          });
          expect(meta[Keys.clientInfoMeta], {
            'name': 'test client',
            'version': '1.0.0',
          });
          observed.complete();
        } catch (error, stackTrace) {
          observed.completeError(error, stackTrace);
        } finally {
          request.response
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                Keys.jsonrpc: '2.0',
                Keys.id: 7,
                Keys.result: {'value': 'done'},
              }),
            );
          await request.response.close();
        }
      });

      final channel = streamableHttpClientChannel(
        Uri.http('${wireServer.address.host}:${wireServer.port}', '/mcp'),
        protocolVersion: ProtocolVersion.v2026_07_28,
        clientCapabilities: ClientCapabilities(sampling: {}),
        clientInfo: Implementation(name: 'test client', version: '1.0.0'),
      );
      addTearDown(() => channel.sink.close());
      final response = channel.stream.first;
      channel.sink.add({
        Keys.jsonrpc: '2.0',
        Keys.id: 7,
        Keys.method: callTool,
        Keys.params: {
          Keys.name: ' café ',
          Keys.arguments: {'value': 1},
          Keys.meta: {'com.example/keep': true},
        },
      });

      final results = await Future.wait<Object?>([response, observed.future]);
      expect(results.first, {
        Keys.jsonrpc: '2.0',
        Keys.id: 7,
        Keys.result: {'value': 'done'},
      });
    });

    test('omits absent client information from request metadata', () async {
      final wireServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => wireServer.close(force: true));
      final observed = Completer<void>();
      wireServer.listen((request) async {
        try {
          final sent =
              jsonDecode(await utf8.decodeStream(request))
                  as Map<String, Object?>;
          final params = sent[Keys.params] as Map<String, Object?>;
          final meta = params[Keys.meta] as Map<String, Object?>;
          expect(meta, isNot(contains(Keys.clientInfoMeta)));
          observed.complete();
        } catch (error, stackTrace) {
          observed.completeError(error, stackTrace);
        } finally {
          request.response
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                Keys.jsonrpc: '2.0',
                Keys.id: 8,
                Keys.result: <String, Object?>{},
              }),
            );
          await request.response.close();
        }
      });

      final channel = streamableHttpClientChannel(
        Uri.http('${wireServer.address.host}:${wireServer.port}', '/mcp'),
        protocolVersion: ProtocolVersion.v2026_07_28,
        clientCapabilities: ClientCapabilities(),
      );
      addTearDown(() => channel.sink.close());
      channel.sink.add({
        Keys.jsonrpc: '2.0',
        Keys.id: 8,
        Keys.method: 'test/request',
      });

      await Future.wait([channel.stream.first, observed.future]);
    });

    test('decodes every message from an SSE response', () async {
      final wireServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => wireServer.close(force: true));
      wireServer.listen((request) async {
        await request.drain<void>();
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
        );
        request.response.write(
          'event: message\n'
          'data: {"jsonrpc":"2.0","method":"notifications/progress"}\n\n'
          'event: message\n'
          'data: {"jsonrpc":"2.0","id":12,"result":{"value":1}}\n\n',
        );
        await request.response.close();
      });

      final channel = streamableHttpClientChannel(
        Uri.http('${wireServer.address.host}:${wireServer.port}', '/mcp'),
        protocolVersion: ProtocolVersion.v2026_07_28,
        clientCapabilities: ClientCapabilities(),
      );
      addTearDown(() => channel.sink.close());
      final events = channel.stream
          .take(2)
          .toList()
          .timeout(const Duration(seconds: 3));
      channel.sink.add({
        Keys.jsonrpc: '2.0',
        Keys.id: 12,
        Keys.method: 'test/request',
      });

      expect(await events, [
        {Keys.jsonrpc: '2.0', Keys.method: progressNotification},
        {
          Keys.jsonrpc: '2.0',
          Keys.id: 12,
          Keys.result: {'value': 1},
        },
      ]);
    });

    test('keeps a failed POST local to its request id', () async {
      final wireServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => wireServer.close(force: true));
      wireServer.listen((request) async {
        final sent =
            jsonDecode(await utf8.decodeStream(request))
                as Map<String, Object?>;
        if (sent[Keys.id] == 20) {
          request.response
            ..statusCode = HttpStatus.badGateway
            ..headers.contentType = ContentType.text
            ..write('upstream stopped');
        } else {
          request.response
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                Keys.jsonrpc: '2.0',
                Keys.id: 21,
                Keys.result: {'value': 'available'},
              }),
            );
        }
        await request.response.close();
      });

      final channel = streamableHttpClientChannel(
        Uri.http('${wireServer.address.host}:${wireServer.port}', '/mcp'),
        protocolVersion: ProtocolVersion.v2026_07_28,
        clientCapabilities: ClientCapabilities(),
      );
      addTearDown(() => channel.sink.close());
      final responses = channel.stream.take(2).toList();
      channel.sink
        ..add({Keys.jsonrpc: '2.0', Keys.id: 20, Keys.method: 'test/failed'})
        ..add({
          Keys.jsonrpc: '2.0',
          Keys.id: 21,
          Keys.method: 'test/available',
        });

      final byId = {
        for (final response in await responses) response[Keys.id]: response,
      };
      final failed = byId[20]![Keys.error] as Map<String, Object?>;
      expect(failed[Keys.code], -32000);
      expect(
        failed[Keys.message],
        allOf(contains('HTTP 502'), contains('upstream stopped')),
      );
      expect(byId[21], {
        Keys.jsonrpc: '2.0',
        Keys.id: 21,
        Keys.result: {'value': 'available'},
      });
    });

    test('does not drop tools from a later result that reuses a failed '
        'tools/list id', () async {
      final wireServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => wireServer.close(force: true));
      final invalidTool = {
        Keys.name: 'invalid',
        Keys.inputSchema: {
          Keys.type: 'object',
          Keys.properties: {
            'ratio': {Keys.type: 'number', Keys.xMcpHeader: 'Ratio'},
          },
        },
      };
      wireServer.listen((request) async {
        final sent =
            jsonDecode(await utf8.decodeStream(request))
                as Map<String, Object?>;
        if (sent[Keys.method] == listTools) {
          request.response
            ..statusCode = HttpStatus.badGateway
            ..headers.contentType = ContentType.text
            ..write('upstream stopped');
        } else {
          request.response
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                Keys.jsonrpc: '2.0',
                Keys.id: 47,
                Keys.result: {
                  Keys.tools: [invalidTool],
                },
              }),
            );
        }
        await request.response.close();
      });

      final channel = streamableHttpClientChannel(
        Uri.http('${wireServer.address.host}:${wireServer.port}', '/mcp'),
        protocolVersion: ProtocolVersion.v2026_07_28,
        clientCapabilities: ClientCapabilities(),
      );
      addTearDown(() => channel.sink.close());
      final iterator = StreamIterator(channel.stream);
      addTearDown(iterator.cancel);
      channel.sink.add({
        Keys.jsonrpc: '2.0',
        Keys.id: 47,
        Keys.method: listTools,
      });
      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current[Keys.error], isNotNull);

      channel.sink.add({
        Keys.jsonrpc: '2.0',
        Keys.id: 47,
        Keys.method: 'test/other',
      });
      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current, {
        Keys.jsonrpc: '2.0',
        Keys.id: 47,
        Keys.result: {
          Keys.tools: [invalidTool],
        },
      });
    });

    test('mirrors tool parameters learned from tools/list', () async {
      final wireServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => wireServer.close(force: true));
      final observedHeader = Completer<void>();
      wireServer.listen((request) async {
        final sent =
            jsonDecode(await utf8.decodeStream(request))
                as Map<String, Object?>;
        if (sent[Keys.method] == listTools) {
          request.response
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                Keys.jsonrpc: '2.0',
                Keys.id: 30,
                Keys.result: {
                  Keys.tools: [
                    {
                      Keys.name: 'valid',
                      Keys.inputSchema: {
                        Keys.type: 'object',
                        Keys.properties: {
                          'context': {
                            Keys.type: 'object',
                            Keys.properties: {
                              'region': {
                                Keys.type: 'string',
                                Keys.xMcpHeader: 'Region',
                              },
                            },
                          },
                        },
                      },
                    },
                    {
                      Keys.name: 'invalid',
                      Keys.inputSchema: {
                        Keys.type: 'object',
                        Keys.properties: {
                          'ratio': {
                            Keys.type: 'number',
                            Keys.xMcpHeader: 'Ratio',
                          },
                        },
                      },
                    },
                  ],
                },
              }),
            );
        } else {
          try {
            expect(
              request.headers.value('Mcp-Param-Region'),
              '=?base64?IGNhZsOpIA==?=',
            );
            observedHeader.complete();
          } catch (error, stackTrace) {
            observedHeader.completeError(error, stackTrace);
          }
          request.response
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                Keys.jsonrpc: '2.0',
                Keys.id: 31,
                Keys.result: <String, Object?>{},
              }),
            );
        }
        await request.response.close();
      });

      final channel = streamableHttpClientChannel(
        Uri.http('${wireServer.address.host}:${wireServer.port}', '/mcp'),
        protocolVersion: ProtocolVersion.v2026_07_28,
        clientCapabilities: ClientCapabilities(),
      );
      addTearDown(() => channel.sink.close());
      final iterator = StreamIterator(channel.stream);
      addTearDown(iterator.cancel);
      channel.sink.add({
        Keys.jsonrpc: '2.0',
        Keys.id: 30,
        Keys.method: listTools,
      });
      expect(await iterator.moveNext(), isTrue);
      final result = iterator.current[Keys.result] as Map<String, Object?>;
      final tools = result[Keys.tools] as List;
      expect(tools, hasLength(1));
      expect((tools.single as Map<String, Object?>)[Keys.name], 'valid');

      channel.sink.add({
        Keys.jsonrpc: '2.0',
        Keys.id: 31,
        Keys.method: callTool,
        Keys.params: {
          Keys.name: 'valid',
          Keys.arguments: {
            'context': {'region': ' café '},
          },
        },
      });
      expect(await iterator.moveNext(), isTrue);
      await observedHeader.future;
    });

    test(
      'keeps a failed notification from producing an inbound message',
      () async {
        final channel = streamableHttpClientChannel(
          uri,
          protocolVersion: ProtocolVersion.v2026_07_28,
          clientCapabilities: ClientCapabilities(),
        );
        addTearDown(() => channel.sink.close());
        final response = channel.stream.first;
        // A non-String method throws before the POST. A notification has no id
        // to attach a JSON-RPC error to.
        channel.sink.add({Keys.jsonrpc: '2.0', Keys.method: 42});
        channel.sink.add({
          Keys.jsonrpc: '2.0',
          Keys.id: 43,
          Keys.method: listTools,
        });

        final message = await response;
        expect(message[Keys.id], 43);
        expect(message[Keys.result], isNotNull);
      },
    );

    test('acknowledges a notification without an inbound message', () async {
      final wireServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => wireServer.close(force: true));
      final notificationReceived = Completer<void>();
      wireServer.listen((request) async {
        final sent =
            jsonDecode(await utf8.decodeStream(request))
                as Map<String, Object?>;
        if (!sent.containsKey(Keys.id)) {
          request.response.statusCode = HttpStatus.accepted;
          notificationReceived.complete();
        } else {
          request.response
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                Keys.jsonrpc: '2.0',
                Keys.id: 40,
                Keys.result: <String, Object?>{},
              }),
            );
        }
        await request.response.close();
      });

      final channel = streamableHttpClientChannel(
        Uri.http('${wireServer.address.host}:${wireServer.port}', '/mcp'),
        protocolVersion: ProtocolVersion.v2026_07_28,
        clientCapabilities: ClientCapabilities(),
      );
      addTearDown(() => channel.sink.close());
      final response = channel.stream.first;
      channel.sink.add({
        Keys.jsonrpc: '2.0',
        Keys.method: progressNotification,
      });
      await notificationReceived.future;
      channel.sink.add({
        Keys.jsonrpc: '2.0',
        Keys.id: 40,
        Keys.method: 'test/request',
      });

      expect(await response, {
        Keys.jsonrpc: '2.0',
        Keys.id: 40,
        Keys.result: <String, Object?>{},
      });
    });

    test('reports a failed notification POST on the channel', () async {
      final wireServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => wireServer.close(force: true));
      wireServer.listen((request) async {
        await utf8.decodeStream(request);
        request.response
          ..statusCode = HttpStatus.internalServerError
          ..headers.contentType = ContentType.text
          ..write('no');
        await request.response.close();
      });

      final channel = streamableHttpClientChannel(
        Uri.http('${wireServer.address.host}:${wireServer.port}', '/mcp'),
        protocolVersion: ProtocolVersion.v2026_07_28,
        clientCapabilities: ClientCapabilities(),
      );
      addTearDown(() => channel.sink.close());
      final failure = channel.stream.first;
      channel.sink.add({
        Keys.jsonrpc: '2.0',
        Keys.method: progressNotification,
      });

      await expectLater(failure, throwsA(isA<UnsupportedError>()));
    });

    test('names an invalid outgoing message in its request error', () async {
      final channel = streamableHttpClientChannel(
        uri,
        protocolVersion: ProtocolVersion.v2026_07_28,
        clientCapabilities: ClientCapabilities(),
      );
      addTearDown(() => channel.sink.close());
      final response = channel.stream.first;
      channel.sink.add({Keys.jsonrpc: '2.0', Keys.id: 41, Keys.result: {}});

      final error = (await response)[Keys.error] as Map<String, Object?>;
      expect(error[Keys.message], contains('(message)'));
    });

    test(
      'names a tools/call whose params are not a string-keyed map',
      () async {
        final channel = streamableHttpClientChannel(
          uri,
          protocolVersion: ProtocolVersion.v2026_07_28,
          clientCapabilities: ClientCapabilities(),
        );
        addTearDown(() => channel.sink.close());
        final response = channel.stream.first;
        channel.sink.add({
          Keys.jsonrpc: '2.0',
          Keys.id: 44,
          Keys.method: callTool,
          Keys.params: <dynamic, dynamic>{
            Keys.name: 'any',
            Keys.arguments: <String, Object?>{},
          },
        });

        final error = (await response)[Keys.error] as Map<String, Object?>;
        expect(error[Keys.message], contains('(${Keys.params})'));
      },
    );

    test(
      'names a tools/call whose arguments are not a string-keyed map',
      () async {
        final channel = streamableHttpClientChannel(
          uri,
          protocolVersion: ProtocolVersion.v2026_07_28,
          clientCapabilities: ClientCapabilities(),
        );
        addTearDown(() => channel.sink.close());
        final response = channel.stream.first;
        channel.sink.add({
          Keys.jsonrpc: '2.0',
          Keys.id: 45,
          Keys.method: callTool,
          Keys.params: {
            Keys.name: 'any',
            Keys.arguments: <dynamic, dynamic>{'x': 1},
          },
        });

        final error = (await response)[Keys.error] as Map<String, Object?>;
        expect(error[Keys.message], contains('(${Keys.arguments})'));
      },
    );

    test(
      'rejects a tools/call with the wrong shape before opening the POST',
      () async {
        // Bind and close so a POST would fail to connect. The shape error
        // must be raised before postUrl, or the error would be the
        // connection failure instead.
        final wireServer = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        final closedUri = Uri.http(
          '${wireServer.address.host}:${wireServer.port}',
          '/mcp',
        );
        await wireServer.close();

        final channel = streamableHttpClientChannel(
          closedUri,
          protocolVersion: ProtocolVersion.v2026_07_28,
          clientCapabilities: ClientCapabilities(),
        );
        addTearDown(() => channel.sink.close());
        final response = channel.stream.first;
        channel.sink.add({
          Keys.jsonrpc: '2.0',
          Keys.id: 46,
          Keys.method: callTool,
          Keys.params: <dynamic, dynamic>{
            Keys.name: 'any',
            Keys.arguments: <String, Object?>{},
          },
        });

        final error = (await response)[Keys.error] as Map<String, Object?>;
        expect(error[Keys.message], contains('(${Keys.params})'));
      },
    );

    test('emits a JSON-RPC error from a 404 response', () async {
      final wireServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => wireServer.close(force: true));
      wireServer.listen((request) async {
        await request.drain<void>();
        request.response
          ..statusCode = HttpStatus.notFound
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              Keys.jsonrpc: '2.0',
              Keys.id: 9,
              Keys.error: {Keys.code: -32601, Keys.message: 'Unknown method'},
            }),
          );
        await request.response.close();
      });

      final channel = streamableHttpClientChannel(
        Uri.http('${wireServer.address.host}:${wireServer.port}', '/mcp'),
        protocolVersion: ProtocolVersion.v2026_07_28,
        clientCapabilities: ClientCapabilities(),
      );
      addTearDown(() => channel.sink.close());
      final response = channel.stream.first;
      channel.sink.add({
        Keys.jsonrpc: '2.0',
        Keys.id: 9,
        Keys.method: 'test/unknown',
      });

      expect(await response, {
        Keys.jsonrpc: '2.0',
        Keys.id: 9,
        Keys.error: {Keys.code: -32601, Keys.message: 'Unknown method'},
      });
    });

    test('emits a request error for a 202 response', () async {
      final wireServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => wireServer.close(force: true));
      wireServer.listen((request) async {
        await request.drain<void>();
        request.response.statusCode = HttpStatus.accepted;
        await request.response.close();
      });

      final channel = streamableHttpClientChannel(
        Uri.http('${wireServer.address.host}:${wireServer.port}', '/mcp'),
        protocolVersion: ProtocolVersion.v2026_07_28,
        clientCapabilities: ClientCapabilities(),
      );
      addTearDown(() => channel.sink.close());
      final response = channel.stream.first;
      channel.sink.add({
        Keys.jsonrpc: '2.0',
        Keys.id: 10,
        Keys.method: 'test/request',
      });

      final error = (await response)[Keys.error] as Map<String, Object?>;
      expect(error[Keys.code], -32000);
      expect(error[Keys.message], contains('Got HTTP 202'));
    });

    test('answers a request whose response stream ends without one', () async {
      final wireServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => wireServer.close(force: true));
      wireServer.listen((request) async {
        await utf8.decodeStream(request);
        request.response
          ..headers.set(HttpHeaders.contentTypeHeader, 'text/event-stream')
          ..write(
            'event: message\ndata: {"jsonrpc":"2.0",'
            '"method":"notifications/progress"}\n\n',
          );
        await request.response.close();
      });

      final channel = streamableHttpClientChannel(
        Uri.http('${wireServer.address.host}:${wireServer.port}', '/mcp'),
        protocolVersion: ProtocolVersion.v2026_07_28,
        clientCapabilities: ClientCapabilities(),
      );
      addTearDown(() => channel.sink.close());
      final messages = channel.stream.take(2).toList();
      channel.sink.add({
        Keys.jsonrpc: '2.0',
        Keys.id: 60,
        Keys.method: listTools,
      });

      expect((await messages).last, {
        Keys.jsonrpc: '2.0',
        Keys.id: 60,
        Keys.error: {
          Keys.code: error_code.SERVER_ERROR,
          Keys.message: contains('ended without a response'),
        },
      });
    });

    test('reports a notification answered with a body', () async {
      final wireServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => wireServer.close(force: true));
      wireServer.listen((request) async {
        await utf8.decodeStream(request);
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              Keys.jsonrpc: '2.0',
              Keys.id: null,
              Keys.error: {Keys.code: -32600, Keys.message: 'no'},
            }),
          );
        await request.response.close();
      });

      final channel = streamableHttpClientChannel(
        Uri.http('${wireServer.address.host}:${wireServer.port}', '/mcp'),
        protocolVersion: ProtocolVersion.v2026_07_28,
        clientCapabilities: ClientCapabilities(),
      );
      addTearDown(() => channel.sink.close());
      final failure = channel.stream.first;
      channel.sink.add({
        Keys.jsonrpc: '2.0',
        Keys.method: progressNotification,
      });

      await expectLater(failure, throwsA(isA<StateError>()));
    });

    test('mirrors an integer parameter written as a decimal', () async {
      final headers = <String?>[];
      final wireServer = await _integerHeaderServer(headers);
      addTearDown(() => wireServer.close(force: true));
      final channel = streamableHttpClientChannel(
        Uri.http('${wireServer.address.host}:${wireServer.port}', '/mcp'),
        protocolVersion: ProtocolVersion.v2026_07_28,
        clientCapabilities: ClientCapabilities(),
      );
      addTearDown(() => channel.sink.close());
      final seen = <Map<String, Object?>>[];
      final listed = Completer<void>();
      final called = Completer<void>();
      channel.stream.listen((message) {
        seen.add(message);
        if (seen.length == 1) listed.complete();
        if (seen.length == 2) called.complete();
      });
      channel.sink.add({
        Keys.jsonrpc: '2.0',
        Keys.id: 70,
        Keys.method: listTools,
      });
      await listed.future;
      channel.sink.add({
        Keys.jsonrpc: '2.0',
        Keys.id: 71,
        Keys.method: callTool,
        Keys.params: {
          Keys.name: 'counted',
          Keys.arguments: {'count': 42.0},
        },
      });

      await called.future;
      expect(headers, ['42']);
    });

    test('refuses a request whose mirrored integer is out of range', () async {
      final headers = <String?>[];
      final wireServer = await _integerHeaderServer(headers);
      addTearDown(() => wireServer.close(force: true));
      final channel = streamableHttpClientChannel(
        Uri.http('${wireServer.address.host}:${wireServer.port}', '/mcp'),
        protocolVersion: ProtocolVersion.v2026_07_28,
        clientCapabilities: ClientCapabilities(),
      );
      addTearDown(() => channel.sink.close());
      final seen = <Map<String, Object?>>[];
      final listed = Completer<void>();
      final called = Completer<void>();
      channel.stream.listen((message) {
        seen.add(message);
        if (seen.length == 1) listed.complete();
        if (seen.length == 2) called.complete();
      });
      channel.sink.add({
        Keys.jsonrpc: '2.0',
        Keys.id: 72,
        Keys.method: listTools,
      });
      await listed.future;
      channel.sink.add({
        Keys.jsonrpc: '2.0',
        Keys.id: 73,
        Keys.method: callTool,
        Keys.params: {
          Keys.name: 'counted',
          Keys.arguments: {'count': 9007199254740992},
        },
      });

      await called.future;
      expect(seen.last, {
        Keys.jsonrpc: '2.0',
        Keys.id: 73,
        Keys.error: {
          Keys.code: error_code.SERVER_ERROR,
          Keys.message: contains('cannot be mirrored onto'),
        },
      });
      expect(headers, isEmpty);
    });

    test('forgets the headers of a tool a later snapshot leaves out', () async {
      final wireServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => wireServer.close(force: true));
      final headers = <String?>[];
      var listed = true;
      wireServer.listen((request) async {
        final sent =
            jsonDecode(await utf8.decodeStream(request))
                as Map<String, Object?>;
        if (sent[Keys.method] == listTools) {
          request.response
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                Keys.jsonrpc: '2.0',
                Keys.id: sent[Keys.id],
                Keys.result: {
                  Keys.tools: [
                    if (listed)
                      {
                        Keys.name: 'regional',
                        Keys.inputSchema: {
                          Keys.type: 'object',
                          Keys.properties: {
                            'region': {
                              Keys.type: 'string',
                              Keys.xMcpHeader: 'Region',
                            },
                          },
                        },
                      },
                  ],
                },
              }),
            );
          listed = false;
        } else {
          headers.add(request.headers.value('Mcp-Param-Region'));
          request.response
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                Keys.jsonrpc: '2.0',
                Keys.id: sent[Keys.id],
                Keys.result: <String, Object?>{},
              }),
            );
        }
        await request.response.close();
      });

      final channel = streamableHttpClientChannel(
        Uri.http('${wireServer.address.host}:${wireServer.port}', '/mcp'),
        protocolVersion: ProtocolVersion.v2026_07_28,
        clientCapabilities: ClientCapabilities(),
      );
      addTearDown(() => channel.sink.close());
      final seen = <Map<String, Object?>>[];
      final steps = [Completer<void>(), Completer<void>(), Completer<void>()];
      channel.stream.listen((message) {
        seen.add(message);
        steps[seen.length - 1].complete();
      });
      channel.sink.add({
        Keys.jsonrpc: '2.0',
        Keys.id: 80,
        Keys.method: listTools,
      });
      await steps[0].future;
      channel.sink.add({
        Keys.jsonrpc: '2.0',
        Keys.id: 81,
        Keys.method: listTools,
      });
      await steps[1].future;
      channel.sink.add({
        Keys.jsonrpc: '2.0',
        Keys.id: 82,
        Keys.method: callTool,
        Keys.params: {
          Keys.name: 'regional',
          Keys.arguments: {'region': 'west'},
        },
      });

      await steps[2].future;
      expect(headers, [null]);
    });

    test('drops a tool annotated under a schema it never reaches', () async {
      final wireServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => wireServer.close(force: true));
      wireServer.listen((request) async {
        final sent =
            jsonDecode(await utf8.decodeStream(request))
                as Map<String, Object?>;
        request.response
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              Keys.jsonrpc: '2.0',
              Keys.id: sent[Keys.id],
              Keys.result: {
                Keys.tools: [
                  {
                    Keys.name: 'hidden',
                    Keys.inputSchema: {
                      Keys.type: 'object',
                      Keys.properties: {
                        'body': {
                          Keys.type: 'string',
                          'contentSchema': {
                            Keys.type: 'object',
                            Keys.properties: {
                              'region': {
                                Keys.type: 'string',
                                Keys.xMcpHeader: 'Region',
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                ],
              },
            }),
          );
        await request.response.close();
      });

      final channel = streamableHttpClientChannel(
        Uri.http('${wireServer.address.host}:${wireServer.port}', '/mcp'),
        protocolVersion: ProtocolVersion.v2026_07_28,
        clientCapabilities: ClientCapabilities(),
      );
      addTearDown(() => channel.sink.close());
      final answer = channel.stream.first;
      channel.sink.add({
        Keys.jsonrpc: '2.0',
        Keys.id: 90,
        Keys.method: listTools,
      });

      final result = (await answer)[Keys.result] as Map<String, Object?>;
      expect(result[Keys.tools], isEmpty);
    });

    test('rejects a protocol version outside its set', () {
      expect(
        () => streamableHttpClientChannel(
          uri,
          protocolVersion: ProtocolVersion.v2025_11_25,
          clientCapabilities: ClientCapabilities(),
        ),
        throwsA(
          isA<ArgumentError>()
              .having(
                (error) => error.invalidValue,
                'invalidValue',
                '2025-11-25',
              )
              .having(
                (error) => error.message,
                'message',
                contains('2026-07-28'),
              ),
        ),
      );
    });

    test('closes an in-flight HTTP request with the channel', () async {
      final wireServer = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      Socket? acceptedSocket;
      addTearDown(() async {
        acceptedSocket?.destroy();
        await wireServer.close();
      });
      final requestStarted = Completer<void>();
      final socketDone = Completer<void>();
      void completeSocket() {
        if (!socketDone.isCompleted) socketDone.complete();
      }

      wireServer.listen((socket) {
        acceptedSocket = socket;
        final requestBytes = <int>[];
        var responseStarted = false;
        socket.listen(
          (bytes) async {
            requestBytes.addAll(bytes);
            if (responseStarted ||
                !latin1.decode(requestBytes).contains('\r\n\r\n')) {
              return;
            }
            responseStarted = true;
            socket.write(
              'HTTP/1.1 200 OK\r\n'
              'Content-Type: application/json\r\n'
              'Content-Length: 2\r\n'
              '\r\n'
              '{',
            );
            await socket.flush();
            requestStarted.complete();
          },
          onError: (_, _) => completeSocket(),
          onDone: completeSocket,
        );
      });

      final channel = streamableHttpClientChannel(
        Uri.http('${wireServer.address.host}:${wireServer.port}', '/mcp'),
        protocolVersion: ProtocolVersion.v2026_07_28,
        clientCapabilities: ClientCapabilities(),
      );
      final channelDone = Completer<void>();
      channel.stream.listen(null, onDone: channelDone.complete);
      channel.sink.add({
        Keys.jsonrpc: '2.0',
        Keys.id: 11,
        Keys.method: 'test/request',
      });

      await requestStarted.future;
      await channel.sink.close();
      await channelDone.future;
      await socketDone.future.timeout(const Duration(seconds: 3));
    });
  });

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
      // Written out so the check does not read back the constant the
      // response was built from.
      expect(errorCode(text), -32020);
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

    test('rejects an Mcp-Name sent as two separate field lines', () async {
      // dart:io's client folds repeated headers into one comma separated
      // line, which the mismatch check catches, so the two-line shape the
      // spec's "single value" rule is really about has to go over a raw
      // socket: dart:io's server keeps the lines separate.
      final requestBody = jsonEncode(
        body(callTool, params: {Keys.name: 'test/version'}),
      );
      final response = await rawRequest(
        'POST /mcp HTTP/1.1\r\n'
        'Host: localhost\r\n'
        'Content-Type: application/json\r\n'
        'Accept: application/json, text/event-stream\r\n'
        'Mcp-Protocol-Version: $version\r\n'
        'Mcp-Method: $callTool\r\n'
        'Mcp-Name: test/version\r\n'
        'Mcp-Name: test/version\r\n'
        'Content-Length: ${requestBody.length}\r\n'
        'Connection: close\r\n'
        '\r\n'
        '$requestBody',
      );
      expect(response, startsWith('HTTP/1.1 400'));
      final error = decode(jsonBody(response))[Keys.error];
      expect(errorCode(jsonBody(response)), McpErrorCodes.headerMismatch);
      // Both values are identical, so only the line count can be what this
      // rejection is about.
      expect(
        error,
        containsPair(Keys.message, contains('Mcp-Name header is required')),
      );
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

  group('x-mcp-header custom headers', () {
    /// A `tools/call` body for `test/withHeaderParam` with [arguments].
    Map<String, Object?> callWithHeaderParam(Map<String, Object?> arguments) =>
        body(
          callTool,
          params: {
            Keys.name: 'test/withHeaderParam',
            Keys.arguments: arguments,
          },
        );

    /// The transport, `Mcp-Method`, and `Mcp-Name` headers for a
    /// `test/withHeaderParam` call, plus any [extra] headers.
    Map<String, String> callWithHeaderParamHeaders([
      Map<String, String> extra = const {},
    ]) => {...headers(callTool), 'Mcp-Name': 'test/withHeaderParam', ...extra};

    test('ignores an annotation the specification does not allow', () async {
      // A tool definition annotating a non-primitive is one the client is
      // told to reject, so nothing here reads `Mcp-Param-Label`.
      final (status, _, text) = await post(
        headers: {
          ...headers(callTool),
          'Mcp-Name': 'test/badAnnotation',
          'Mcp-Param-Label': 'wrong',
        },
        json: body(
          callTool,
          params: {
            Keys.name: 'test/badAnnotation',
            Keys.arguments: {'label': 'right'},
          },
        ),
      );
      expect(status, 200);
      expect(errorCode(text), isNull);
    });

    test(
      'ignores an Mcp-Param header for a tool that annotates none',
      () async {
        // `test/version` marks no property with `x-mcp-header`, so there is
        // no argument to compare the header against, and it is ignored.
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
      },
    );

    test('skips a schema part that cannot carry an annotation', () async {
      final (status, _, text) = await post(
        headers: {...headers(callTool), 'Mcp-Name': 'test/booleanSubschema'},
        json: body(
          callTool,
          params: {
            Keys.name: 'test/booleanSubschema',
            Keys.arguments: {
              'anything': 'x',
              'nested': {'region': 'us-west1'},
            },
          },
        ),
      );
      expect(status, 200);
      expect(errorCode(text), isNull);
    });

    test('skips a tool whose properties are not an object', () async {
      final (status, _, text) = await post(
        headers: {...headers(callTool), 'Mcp-Name': 'test/nonObjectProperties'},
        json: body(callTool, params: {Keys.name: 'test/nonObjectProperties'}),
      );
      expect(status, 200);
      expect(errorCode(text), isNull);
    });

    test('accepts a matching value without listing tools', () async {
      final (status, _, text) = await post(
        headers: callWithHeaderParamHeaders({'Mcp-Param-Region': 'us-west1'}),
        json: callWithHeaderParam({'region': 'us-west1'}),
      );
      expect(status, 200);
      expect(errorCode(text), isNull);
      expect(servers.single.listToolsCalls, 0);
    });

    test('rejects arguments that are not an object', () async {
      final (status, _, text) = await post(
        headers: callWithHeaderParamHeaders({'Mcp-Param-Region': 'us-west1'}),
        json: body(
          callTool,
          params: {
            Keys.name: 'test/withHeaderParam',
            Keys.arguments: 'us-west1',
          },
        ),
      );
      expect(status, 400);
      expect(errorCode(text), error_code.INVALID_PARAMS);
      expect(errorMessage(text), contains('params.arguments'));
    });

    test('rejects a non-ASCII header field value', () async {
      final bodyBytes = utf8.encode(
        jsonEncode(callWithHeaderParam({'region': 'é'})),
      );
      final response = await rawRequest(
        'POST /mcp HTTP/1.1\r\n'
        'Host: ${httpServer.address.host}:${httpServer.port}\r\n'
        'Content-Type: application/json\r\n'
        'Accept: application/json, text/event-stream\r\n'
        'Mcp-Protocol-Version: $version\r\n'
        'Mcp-Method: $callTool\r\n'
        'Mcp-Name: test/withHeaderParam\r\n'
        'Mcp-Param-Region: é\r\n'
        'Content-Length: ${bodyBytes.length}\r\n'
        'Connection: close\r\n'
        '\r\n',
        bodyBytes,
      );
      expect(response, startsWith('HTTP/1.1 400'));
      expect(errorCode(jsonBody(response)), McpErrorCodes.headerMismatch);
    });

    test('rejects a header value that does not match the body', () async {
      final (status, _, text) = await post(
        headers: callWithHeaderParamHeaders({'Mcp-Param-Region': 'eu-west1'}),
        json: callWithHeaderParam({'region': 'us-west1'}),
      );
      expect(status, 400);
      expect(errorCode(text), McpErrorCodes.headerMismatch);
      expect(errorMessage(text), contains('eu-west1'));
      expect(errorMessage(text), contains('us-west1'));
    });

    test('rejects a request missing a header its body requires', () async {
      final (status, _, text) = await post(
        headers: callWithHeaderParamHeaders(),
        json: callWithHeaderParam({'region': 'us-west1'}),
      );
      expect(status, 400);
      expect(errorCode(text), McpErrorCodes.headerMismatch);
      expect(errorMessage(text), contains('no single Mcp-Param-Region'));
      expect(errorMessage(text), contains('us-west1'));
    });

    test('rejects a header for an absent argument', () async {
      final (status, _, text) = await post(
        headers: callWithHeaderParamHeaders({'Mcp-Param-Region': 'us-west1'}),
        json: callWithHeaderParam(const {}),
      );
      expect(status, 400);
      expect(errorCode(text), McpErrorCodes.headerMismatch);
      expect(errorMessage(text), contains('Mcp-Param-Region'));
      expect(errorMessage(text), contains('params.arguments.region'));
    });

    test('rejects a header for a null argument', () async {
      final (status, _, text) = await post(
        headers: callWithHeaderParamHeaders({'Mcp-Param-Region': 'us-west1'}),
        json: callWithHeaderParam({'region': null}),
      );
      expect(status, 400);
      expect(errorCode(text), McpErrorCodes.headerMismatch);
      expect(errorMessage(text), contains('Mcp-Param-Region'));
      expect(errorMessage(text), contains('params.arguments.region'));
    });

    test('rejects before an initialization notification commits', () async {
      // Holding the notification back is what leaves the response headers
      // free to carry a 400, and the price is that the rejected call sends
      // none of them.
      final notifying = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => notifying.close(force: true));
      notifying.listen(
        (request) =>
            handleStreamableHttpRequest(request, _NotifyingInitServer.new),
      );
      final client = HttpClient();
      addTearDown(client.close);
      final request = await client.postUrl(
        Uri.http('${notifying.address.host}:${notifying.port}', '/mcp'),
      );
      callWithHeaderParamHeaders().forEach(request.headers.set);
      request.write(jsonEncode(callWithHeaderParam({'region': 'us-west1'})));
      final response = await request.close();
      final text = await utf8.decodeStream(response);

      expect(response.statusCode, 400);
      expect(response.headers.contentType?.mimeType, 'application/json');
      expect(errorCode(text), McpErrorCodes.headerMismatch);
      expect(text, isNot(contains('while starting up')));
    });

    test(
      'does not require a header for an argument the body leaves null',
      () async {
        final (status, _, text) = await post(
          headers: callWithHeaderParamHeaders(),
          json: callWithHeaderParam({'region': null}),
        );
        expect(status, 200);
        expect(errorCode(text), isNull);
      },
    );

    test('decodes a base64-sentinel header value before comparing', () async {
      final encoded = base64.encode(utf8.encode('us-west1'));
      final (status, _, text) = await post(
        headers: callWithHeaderParamHeaders({
          'Mcp-Param-Region': '=?base64?$encoded?=',
        }),
        json: callWithHeaderParam({'region': 'us-west1'}),
      );
      expect(status, 200);
      expect(errorCode(text), isNull);
    });

    test('rejects a base64-sentinel header value with bad padding', () async {
      final (status, _, text) = await post(
        // The base64 encoding of "us-west1" is "dXMtd2VzdDE=", with its
        // required padding character stripped here.
        headers: callWithHeaderParamHeaders({
          'Mcp-Param-Region': '=?base64?dXMtd2VzdDE?=',
        }),
        json: callWithHeaderParam({'region': 'us-west1'}),
      );
      expect(status, 400);
      expect(errorCode(text), McpErrorCodes.headerMismatch);
      expect(errorMessage(text), contains('=?base64?dXMtd2VzdDE?='));
      expect(errorMessage(text), contains('not valid base64'));
    });

    test('compares an integer property numerically', () async {
      // The specification's own example of a numeric comparison: the header
      // spells the number differently and still matches.
      for (final header in ['42', '42.0']) {
        final (status, _, text) = await post(
          headers: callWithHeaderParamHeaders({'Mcp-Param-Count': header}),
          json: callWithHeaderParam({'count': 42}),
        );
        expect(status, 200, reason: header);
        expect(errorCode(text), isNull, reason: header);
      }
    });

    test('rejects an integer header that is not a decimal', () async {
      // A client is told to send the decimal spelling, so anything else in the
      // header is a value some other component wrote. Letting `0x2a` match a
      // body of `42` would be the disagreement this check exists to catch.
      // Leading whitespace never reaches here: the HTTP layer trims a header
      // value before this sees it.
      for (final header in ['0x2a', '0X2A', '+42', '42.']) {
        final (status, _, text) = await post(
          headers: callWithHeaderParamHeaders({'Mcp-Param-Count': header}),
          json: callWithHeaderParam({'count': 42}),
        );
        expect(status, 400, reason: header);
        expect(errorCode(text), McpErrorCodes.headerMismatch, reason: header);
      }

      final (status, _, text) = await post(
        headers: callWithHeaderParamHeaders({'Mcp-Param-Count': '1e3'}),
        json: callWithHeaderParam({'count': 1000}),
      );
      expect(status, 400);
      expect(errorCode(text), McpErrorCodes.headerMismatch);
    });

    test('rejects a mismatched integer property', () async {
      final (status, _, text) = await post(
        headers: callWithHeaderParamHeaders({'Mcp-Param-Count': '7'}),
        json: callWithHeaderParam({'count': 42}),
      );
      expect(status, 400);
      expect(errorCode(text), McpErrorCodes.headerMismatch);
    });

    test('compares a boolean property', () async {
      final (status, _, text) = await post(
        headers: callWithHeaderParamHeaders({'Mcp-Param-Flag': 'true'}),
        json: callWithHeaderParam({'flag': true}),
      );
      expect(status, 200);
      expect(errorCode(text), isNull);
    });

    test('rejects a mismatched boolean property', () async {
      final (status, _, text) = await post(
        headers: callWithHeaderParamHeaders({'Mcp-Param-Flag': 'false'}),
        json: callWithHeaderParam({'flag': true}),
      );
      expect(status, 400);
      expect(errorCode(text), McpErrorCodes.headerMismatch);
    });
  });

  group('nested x-mcp-header custom headers', () {
    /// A `tools/call` body for `test/withNestedHeaderParam` with
    /// [arguments].
    Map<String, Object?> callWithNestedHeaderParam(
      Map<String, Object?> arguments,
    ) => body(
      callTool,
      params: {
        Keys.name: 'test/withNestedHeaderParam',
        Keys.arguments: arguments,
      },
    );

    /// The transport, `Mcp-Method`, and `Mcp-Name` headers for a
    /// `test/withNestedHeaderParam` call, plus any [extra] headers.
    Map<String, String> callWithNestedHeaderParamHeaders([
      Map<String, String> extra = const {},
    ]) => {
      ...headers(callTool),
      'Mcp-Name': 'test/withNestedHeaderParam',
      ...extra,
    };

    test('accepts a header matching a nested property', () async {
      final (status, _, text) = await post(
        headers: callWithNestedHeaderParamHeaders({
          'Mcp-Param-Region': 'us-west1',
        }),
        json: callWithNestedHeaderParam({
          'location': {'region': 'us-west1'},
        }),
      );
      expect(status, 200);
      expect(errorCode(text), isNull);
    });

    test('rejects a header that does not match a nested property', () async {
      final (status, _, text) = await post(
        headers: callWithNestedHeaderParamHeaders({
          'Mcp-Param-Region': 'eu-west1',
        }),
        json: callWithNestedHeaderParam({
          'location': {'region': 'us-west1'},
        }),
      );
      expect(status, 400);
      expect(errorCode(text), McpErrorCodes.headerMismatch);
    });

    test(
      'rejects a request missing the header a nested property requires',
      () async {
        final (status, _, text) = await post(
          headers: callWithNestedHeaderParamHeaders(),
          json: callWithNestedHeaderParam({
            'location': {'region': 'us-west1'},
          }),
        );
        expect(status, 400);
        expect(errorCode(text), McpErrorCodes.headerMismatch);
      },
    );

    test('skips a subtree whose carrying argument is not an object', () async {
      final (status, _, text) = await post(
        headers: callWithNestedHeaderParamHeaders({
          'Mcp-Param-Region': 'us-west1',
        }),
        json: callWithNestedHeaderParam({'location': 'us-west1'}),
      );
      expect(status, 200);
      expect(errorCode(text), isNull);
    });

    test('rejects a header for an absent nested argument', () async {
      final (status, _, text) = await post(
        headers: callWithNestedHeaderParamHeaders({
          'Mcp-Param-Region': 'us-west1',
        }),
        json: callWithNestedHeaderParam(const {}),
      );
      expect(status, 400);
      expect(errorCode(text), McpErrorCodes.headerMismatch);
    });

    test('does not require a header when the object carrying a nested '
        'property is absent', () async {
      final (status, _, text) = await post(
        headers: callWithNestedHeaderParamHeaders(),
        json: callWithNestedHeaderParam(const {}),
      );
      expect(status, 200);
      expect(errorCode(text), isNull);
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

    group('methods the revision removed', () {
      // This server mixes in `LoggingSupport` and `ResourcesSupport`, which
      // the other server in this file does not. Three of the removed methods
      // get their handlers from those. `ping` comes from `MCPBase`,
      // and the roots handler from `MCPServer`, so the roots test below uses
      // the default server. Before this gate each of them reached a handler
      // when the body carried an id.
      late HttpServer equipped;
      late HttpClient client;

      setUp(() async {
        equipped = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => equipped.close(force: true));
        equipped.listen(
          (request) =>
              handleStreamableHttpRequest(request, _EquippedServer.new),
        );
        client = HttpClient();
        addTearDown(client.close);
      });

      for (final method in [ping, setLevel, subscribe, unsubscribe]) {
        test('answers $method with 404', () async {
          final request = await client.postUrl(
            Uri.http('${equipped.address.host}:${equipped.port}', '/mcp'),
          );
          headers(method).forEach(request.headers.set);
          request.write(jsonEncode(body(method)));
          final response = await request.close();
          final text = await utf8.decodeStream(response);
          expect(response.statusCode, 404);
          expect(errorCode(text), error_code.METHOD_NOT_FOUND);
        });
      }

      test('acknowledges $ping as a notification with 202', () async {
        // Dropping the id makes this a notification, which is acknowledged
        // before the gate runs.
        final (status, _, text) = await post(
          headers: headers(ping),
          json: body(ping, id: null),
        );
        expect(status, 202);
        expect(text, isEmpty);
      });

      test('answers $rootsListChangedNotification with 404', () async {
        // The capability is what would have registered a handler for this
        // method, which is what the gate has to get in front of. The id
        // makes this a request.
        final (status, _, text) = await post(
          headers: headers(rootsListChangedNotification),
          json: body(
            rootsListChangedNotification,
            capabilities: {
              'roots': {'listChanged': true},
            },
          ),
        );
        expect(status, 404);
        expect(errorCode(text), error_code.METHOD_NOT_FOUND);
      });
    });
  });

  group('per-request log level', () {
    /// A `tools/call` body for the tool that logs, carrying [logLevel] in its
    /// envelope when one is given.
    Map<String, Object?> logBody({Object? logLevel}) {
      final request = body(callTool, params: {Keys.name: 'test/log'});
      final params = request[Keys.params] as Map<String, Object?>;
      final meta = params[Keys.meta] as Map<String, Object?>;
      if (logLevel != null) meta[Keys.logLevelMeta] = logLevel;
      return request;
    }

    Map<String, String> logHeaders() => {
      ...headers(callTool),
      'Mcp-Name': 'test/log',
    };

    test('drops a tool log when the envelope named no level', () async {
      final (status, _, text) = await post(
        headers: logHeaders(),
        json: logBody(),
      );
      expect(status, 200);
      expect(errorCode(text), isNull);
      expect(notifications, isEmpty);
    });

    test('sends log messages at the level the envelope asked for', () async {
      final (status, _, text) = await post(
        headers: logHeaders(),
        json: logBody(logLevel: LoggingLevel.error.name),
      );
      expect(status, 200);
      final messages = events(text);
      expect(
        messages.first[Keys.method],
        LoggingMessageNotification.methodName,
      );
      expect(messages.last[Keys.error], isNull);
      expect(
        notifications.single[Keys.method],
        LoggingMessageNotification.methodName,
      );
    });

    test('drops log messages below the level the envelope asked for', () async {
      final (status, _, text) = await post(
        headers: logHeaders(),
        json: logBody(logLevel: LoggingLevel.emergency.name),
      );
      expect(status, 200);
      expect(errorCode(text), isNull);
      expect(notifications, isEmpty);
    });

    test('rejects a value that is not a logging level', () async {
      final (status, _, text) = await post(
        headers: logHeaders(),
        json: logBody(logLevel: 'chatty'),
      );
      expect(status, 400);
      expect(errorCode(text), error_code.INVALID_PARAMS);
      expect(
        errorMessage(text),
        allOf([
          contains('"chatty"'),
          for (final level in LoggingLevel.values) contains(level.name),
        ]),
        reason: 'the rejection names the value and every level it could be',
      );
      expect(servers, isEmpty);
    });

    test('rejects a value that is not a String', () async {
      final (status, _, text) = await post(
        headers: logHeaders(),
        json: logBody(logLevel: 3),
      );
      expect(status, 400);
      expect(errorCode(text), error_code.INVALID_PARAMS);
      expect(errorMessage(text), contains('"3"'));
      expect(servers, isEmpty);
    });
  });

  group('http methods', () {
    for (final method in ['GET', 'DELETE', 'PUT']) {
      test('rejects $method with 405', () async {
        final (status, responseHeaders, text) = await post(
          method: method,
          headers: method == 'DELETE' ? {'Mcp-Session-Id': 'abc'} : const {},
        );
        expect(status, 405);
        expect(responseHeaders.value(HttpHeaders.allowHeader), 'POST');
        expect(text, isEmpty);
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
      expect(errorCode(text), -32022);
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

    test('maps a crashed handler to 500', () async {
      // A handler which throws something other than an RpcException surfaces
      // as a server error, the same class of failure as a server which cannot
      // be built, which is answered with 500 as well.
      final (status, _, text) = await post(
        headers: headers('test/crash'),
        json: body('test/crash'),
      );
      expect(status, 500);
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

    test('keeps an error the spec defines no status for at 200', () async {
      final (status, _, text) = await post(
        headers: {...headers(callTool), 'Mcp-Name': 'test/unmappedCode'},
        json: body(callTool, params: {Keys.name: 'test/unmappedCode'}),
      );
      expect(status, 200);
      expect(errorCode(text), -32099);
    });

    test('maps an internal error from a dispatched response to 500', () async {
      final (status, _, text) = await post(
        headers: {...headers(callTool), 'Mcp-Name': 'test/internalError'},
        json: body(callTool, params: {Keys.name: 'test/internalError'}),
      );
      expect(status, 500);
      expect(errorCode(text), error_code.INTERNAL_ERROR);
    });

    test('maps a missing client capability error to 400', () async {
      final (status, _, text) = await post(
        headers: {...headers(callTool), 'Mcp-Name': 'test/needsSampling'},
        json: body(callTool, params: {Keys.name: 'test/needsSampling'}),
      );
      expect(status, 400);
      expect(errorCode(text), -32021);
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

    test('rejects an envelope version which is not a String', () async {
      final (status, _, text) = await post(
        headers: headers(listTools),
        json: body(listTools, bodyVersion: 42),
      );
      expect(status, 400);
      expect(errorCode(text), error_code.INVALID_PARAMS);
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
      final messages = events(text);
      expect(
        messages.first[Keys.method],
        LoggingMessageNotification.methodName,
      );
      expect(messages.last[Keys.error], isNull);
      expect(notifications, hasLength(1));
      expect(
        notifications.single[Keys.method],
        LoggingMessageNotification.methodName,
      );
    });
  });

  group('response shape', () {
    test('keeps a list change off the response stream', () async {
      const tool = 'test/registers-then-fails';
      final (status, responseHeaders, text) = await post(
        headers: {...headers(callTool), 'Mcp-Name': tool},
        json: body(callTool, params: {Keys.name: tool}),
      );

      // The list change belongs on a `subscriptions/listen` stream. Writing it
      // here would commit the response and spend the 400 this revision
      // requires of the error the handler goes on to throw.
      expect(status, 400);
      expect(responseHeaders.contentType?.mimeType, 'application/json');
      expect(errorCode(text), -32021);
      expect(
        notifications.map((notification) => notification[Keys.method]),
        contains(ToolListChangedNotification.methodName),
      );
    });

    test('answers a quiet handler with a json body', () async {
      final (status, responseHeaders, text) = await post(
        headers: {...headers(listTools)},
        json: body(listTools),
      );
      expect(status, 200);
      expect(responseHeaders.contentType?.mimeType, 'application/json');
      expect(decode(text)[Keys.error], isNull);
    });

    test('delivers a notification before the result', () async {
      releaseNotifyThenWait = Completer<void>();
      addTearDown(() {
        if (!releaseNotifyThenWait.isCompleted) {
          releaseNotifyThenWait.complete();
        }
      });
      final client = HttpClient();
      addTearDown(client.close);
      final request = await client.openUrl('POST', uri);
      headers(callTool).forEach(request.headers.set);
      request.headers.set('Mcp-Name', 'test/notify-then-wait');
      request.write(
        jsonEncode(
          body(callTool, params: {Keys.name: 'test/notify-then-wait'}),
        ),
      );
      final response = await request.close();

      // The handler is still parked. Anything read here arrived before the
      // result did, and a buffered response would deliver nothing until close.
      final chunks = StringBuffer();
      final firstFrame = Completer<String>();
      final subscription = response.transform(utf8.decoder).listen((chunk) {
        chunks.write(chunk);
        if (!firstFrame.isCompleted && chunks.toString().contains('\n\n')) {
          firstFrame.complete(chunks.toString());
        }
      });
      addTearDown(subscription.cancel);

      final early = await firstFrame.future;
      expect(
        events(early).single[Keys.method],
        LoggingMessageNotification.methodName,
      );

      releaseNotifyThenWait.complete();
      await subscription.asFuture<void>();
      expect(events(chunks.toString()), hasLength(2));
    });

    test('keeps the stream open for a second notification', () async {
      final (status, responseHeaders, text) = await post(
        headers: {...headers(callTool), 'Mcp-Name': 'test/notify-twice'},
        json: body(callTool, params: {Keys.name: 'test/notify-twice'}),
      );
      expect(status, 200);
      expect(responseHeaders.contentType?.mimeType, 'text/event-stream');
      final messages = events(text);
      expect(messages, hasLength(3));
      expect(
        messages.take(2).map((m) => m[Keys.method]),
        everyElement(LoggingMessageNotification.methodName),
      );
      expect(messages.last[Keys.id], isNotNull);
    });

    test('answers an unknown method with 404 and a json body', () async {
      const unknown = 'test/nothing-defines-this';
      final (status, responseHeaders, text) = await post(
        headers: headers(unknown),
        json: body(unknown),
      );
      expect(status, 404);
      expect(responseHeaders.contentType?.mimeType, 'application/json');
      expect(errorCode(text), error_code.METHOD_NOT_FOUND);
    });

    test('sets the streaming headers with the first event', () async {
      final (_, responseHeaders, text) = await post(
        headers: {...headers(callTool), 'Mcp-Name': 'test/notify'},
        json: body(callTool, params: {Keys.name: 'test/notify'}),
      );
      expect(responseHeaders.contentType?.charset, 'utf-8');
      expect(
        responseHeaders.value(HttpHeaders.cacheControlHeader),
        contains('no-cache'),
      );
      // A SHOULD of this revision. A reverse proxy that honors it stops
      // holding the events back until the response closes.
      expect(responseHeaders.value('x-accel-buffering'), 'no');
      expect(
        frames(text).map((frame) => frame['event']),
        everyElement('message'),
      );
    });

    test('hands its own stream to sseMessageStream', () async {
      final (_, _, text) = await post(
        headers: {...headers(callTool), 'Mcp-Name': 'test/notify'},
        json: body(callTool, params: {Keys.name: 'test/notify'}),
      );
      // The decoder's own tests spell their input out by hand. This one
      // reads back what the transport wrote.
      final messages =
          await sseMessageStream(Stream.value(utf8.encode(text))).toList();

      expect(messages, hasLength(2));
      expect(
        messages.first[Keys.method],
        LoggingMessageNotification.methodName,
      );
      expect(messages.last[Keys.id], isNotNull);
    });

    test('sends a late error as the last event on the stream', () async {
      final (status, responseHeaders, text) = await post(
        headers: {...headers(callTool), 'Mcp-Name': 'test/notify-then-throw'},
        json: body(callTool, params: {Keys.name: 'test/notify-then-throw'}),
      );
      // The status is spent on the first notification. The mapped 400 this
      // error carries when it arrives alone is no longer reachable.
      expect(status, 200);
      expect(responseHeaders.contentType?.mimeType, 'text/event-stream');
      final messages = events(text);
      expect(messages, hasLength(2));
      expect(
        (messages.last[Keys.error] as Map<String, Object?>)[Keys.code],
        error_code.INVALID_PARAMS,
      );
    });

    test('keeps a prompt list change off the response stream', () async {
      final noisy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => noisy.close(force: true));
      const tool = 'test/adds-prompt';
      noisy.listen(
        (request) =>
            handleStreamableHttpRequest(request, _PromptNoisyServer.new),
      );
      final client = HttpClient();
      addTearDown(client.close);
      final request = await client.postUrl(
        Uri.http('${noisy.address.host}:${noisy.port}', '/mcp'),
      );
      final callHeaders = {...headers(callTool), 'Mcp-Name': tool};
      callHeaders.forEach(request.headers.set);
      request.write(jsonEncode(body(callTool, params: {Keys.name: tool})));
      final response = await request.close();
      final text = await utf8.decodeStream(response);

      expect(response.statusCode, 200);
      expect(response.headers.contentType?.mimeType, 'application/json');
      expect(text, isNot(contains(PromptListChangedNotification.methodName)));
    });

    test('closes the stream when a notifying server fails', () async {
      final failing = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => failing.close(force: true));
      final failure = Completer<Object>();
      failing.listen(
        (request) => handleStreamableHttpRequest(
          request,
          _NoisyFailingServer.new,
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
      // Without an answer through the stream this read never returns. The
      // headers are already sent, and starting a fresh response throws inside
      // the error path and leaves the connection open.
      final text = await utf8.decodeStream(response);
      expect(response.statusCode, 200);
      expect(response.headers.contentType?.mimeType, 'text/event-stream');
      final messages = events(text);
      expect(messages, hasLength(2));
      expect(
        (messages.last[Keys.error] as Map<String, Object?>)[Keys.code],
        error_code.INTERNAL_ERROR,
      );
      expect(await failure.future, isStateError);
    });

    test('answers a failed tools/call on the stream too', () async {
      // `tools/call` is the one method that holds notifications back until
      // the header check passes, so it is the one that could answer a server
      // failing after it announced itself with a fresh response instead.
      final failing = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => failing.close(force: true));
      failing.listen(
        (request) => handleStreamableHttpRequest(
          request,
          _NoisyFailingServer.new,
        ).onError<Object>((_, _) {}),
      );
      final client = HttpClient();
      addTearDown(client.close);
      final request = await client.postUrl(
        Uri.http('${failing.address.host}:${failing.port}', '/mcp'),
      );
      final callHeaders = {...headers(callTool), 'Mcp-Name': 'test/version'};
      callHeaders.forEach(request.headers.set);
      request.write(
        jsonEncode(body(callTool, params: {Keys.name: 'test/version'})),
      );
      final response = await request.close();
      final text = await utf8.decodeStream(response);
      expect(response.statusCode, 200);
      expect(response.headers.contentType?.mimeType, 'text/event-stream');
      final messages = events(text);
      expect(messages, hasLength(2));
      expect(
        (messages.last[Keys.error] as Map<String, Object?>)[Keys.code],
        error_code.INTERNAL_ERROR,
      );
    });

    test('writes the event before the handler callback sees it', () async {
      final rude = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => rude.close(force: true));
      final swallowed = <Object>[];
      runZonedGuarded(
        () => rude.listen(
          (request) => handleStreamableHttpRequest(
            request,
            _HttpTestServer.new,
            onNotification: (_) => throw StateError('a rude embedder'),
          ),
        ),
        (error, _) => swallowed.add(error),
      );
      final client = HttpClient();
      addTearDown(client.close);
      final request = await client.postUrl(
        Uri.http('${rude.address.host}:${rude.port}', '/mcp'),
      );
      final sent = {...headers(callTool), 'Mcp-Name': 'test/notify'};
      sent.forEach(request.headers.set);
      request.write(
        jsonEncode(body(callTool, params: {Keys.name: 'test/notify'})),
      );
      final response = await request.close();
      final text = await utf8.decodeStream(response);
      // An embedder which throws must not be able to keep a notification off
      // the protocol stream. Writing it first prevents that.
      expect(response.statusCode, 200);
      expect(response.headers.contentType?.mimeType, 'text/event-stream');
      expect(events(text), hasLength(2));
      expect(swallowed, isNotEmpty);
    });
  });
}

/// Held by `test/notify-then-wait` until a test releases it.
Completer<void> releaseNotifyThenWait = Completer<void>();

base class _HttpTestServer extends MCPServer with LoggingSupport, ToolsSupport {
  bool get _declaredSampling => clientCapabilities.sampling != null;
  int listToolsCalls = 0;

  @override
  FutureOr<ListToolsResult> listTools([ListToolsRequest? request]) {
    listToolsCalls++;
    return super.listTools(request);
  }

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
      Tool(
        name: 'test/withHeaderParam',
        inputSchema: ObjectSchema(
          properties: {
            // `x-mcp-header` is a schema extension the typed [Schema]
            // factories do not have a parameter for, so these are built
            // from a raw map instead.
            'region': Schema.fromMap({
              Keys.type: JsonType.string.typeName,
              Keys.xMcpHeader: 'Region',
            }),
            'count': Schema.fromMap({
              Keys.type: JsonType.int.typeName,
              Keys.xMcpHeader: 'Count',
            }),
            'flag': Schema.fromMap({
              Keys.type: JsonType.bool.typeName,
              Keys.xMcpHeader: 'Flag',
            }),
          },
        ),
      ),
      (_) => CallToolResult(content: [TextContent(text: 'ok')]),
      validateArguments: false,
    );
    registerTool(
      Tool(
        name: 'test/badAnnotation',
        inputSchema: ObjectSchema(
          properties: {
            // A non-primitive carrying the annotation.
            'label': Schema.fromMap({
              Keys.type: <Object?>[
                JsonType.string.typeName,
                JsonType.nil.typeName,
              ],
              Keys.xMcpHeader: 'Label',
            }),
          },
        ),
      ),
      (_) => CallToolResult(content: [TextContent(text: 'ok')]),
      validateArguments: false,
    );
    registerTool(
      Tool(
        name: 'test/booleanSubschema',
        // A boolean subschema, and a nested `properties` that is a number.
        inputSchema: ObjectSchema.fromMap({
          Keys.type: JsonType.object.typeName,
          Keys.properties: {
            'anything': true,
            'nested': {Keys.properties: 5},
          },
        }),
      ),
      (_) => CallToolResult(content: [TextContent(text: 'ok')]),
      validateArguments: false,
    );
    registerTool(
      Tool(
        name: 'test/nonObjectProperties',
        inputSchema: ObjectSchema.fromMap({
          Keys.type: JsonType.object.typeName,
          Keys.properties: <Object>[1, 2],
        }),
      ),
      (_) => CallToolResult(content: [TextContent(text: 'ok')]),
      validateArguments: false,
    );
    registerTool(
      Tool(
        name: 'test/withNestedHeaderParam',
        inputSchema: ObjectSchema(
          properties: {
            'location': Schema.fromMap({
              Keys.properties: <String, Schema>{
                'region': Schema.fromMap({
                  Keys.type: JsonType.string.typeName,
                  Keys.xMcpHeader: 'Region',
                }),
              },
            }),
          },
        ),
      ),
      (_) => CallToolResult(content: [TextContent(text: 'ok')]),
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
    registerTool(
      Tool(name: 'test/unmappedCode', inputSchema: ObjectSchema()),
      // The far end of the range the specification reserves for itself, which
      // no revision has allocated, so nothing defines a status for it.
      (_) =>
          throw RpcException(
            -32099,
            'This tool fails with a code no status is defined for',
          ),
    );
    registerTool(
      Tool(name: 'test/internalError', inputSchema: ObjectSchema()),
      (_) =>
          throw RpcException(
            error_code.INTERNAL_ERROR,
            'This tool reports an internal error',
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
    registerTool(Tool(name: 'test/notify-twice', inputSchema: ObjectSchema()), (
      _,
    ) {
      for (final data in ['first', 'second']) {
        sendNotification(
          LoggingMessageNotification.methodName,
          LoggingMessageNotification(level: LoggingLevel.error, data: data),
        );
      }
      return CallToolResult(content: [TextContent(text: 'twice')]);
    });
    registerTool(
      Tool(name: 'test/notify-then-wait', inputSchema: ObjectSchema()),
      (_) async {
        sendNotification(
          LoggingMessageNotification.methodName,
          LoggingMessageNotification(
            level: LoggingLevel.error,
            data: 'before the wait',
          ),
        );
        await releaseNotifyThenWait.future;
        return CallToolResult(content: [TextContent(text: 'released')]);
      },
    );
    registerTool(
      Tool(name: 'test/notify-then-throw', inputSchema: ObjectSchema()),
      (_) {
        sendNotification(
          LoggingMessageNotification.methodName,
          LoggingMessageNotification(
            level: LoggingLevel.error,
            data: 'before the failure',
          ),
        );
        throw RpcException.invalidParams('This tool fails after notifying');
      },
    );
    registerTool(
      Tool(name: 'test/registers-then-fails', inputSchema: ObjectSchema()),
      (_) {
        // Registering a tool emits a list change on its own, which is what a
        // dynamic tool set does while it answers.
        registerTool(
          Tool(name: 'test/added-while-answering', inputSchema: ObjectSchema()),
          (_) => CallToolResult(content: [TextContent(text: 'added')]),
        );
        throw RpcException(
          McpErrorCodes.missingRequiredClientCapability,
          'This tool needs a capability the client left out',
        );
      },
    );
    registerTool(Tool(name: 'test/log', inputSchema: ObjectSchema()), (_) {
      log(LoggingLevel.error, 'from tool');
      return CallToolResult(content: [TextContent(text: 'logged')]);
    });
  }
}

/// A server that emits a notification while a request is initializing.
base class _NotifyingInitServer extends _HttpTestServer {
  _NotifyingInitServer(super.channel);

  @override
  FutureOr<void> initialize(MCPServerInitialization initialization) async {
    await super.initialize(initialization);
    sendNotification(
      LoggingMessageNotification.methodName,
      LoggingMessageNotification(
        level: LoggingLevel.error,
        data: 'while starting up',
      ),
    );
  }
}

/// A server whose tool registers a prompt while it answers, so the prompt list
/// change lands mid-request the way a dynamic prompt set makes it.
base class _PromptNoisyServer extends MCPServer
    with LoggingSupport, ToolsSupport, PromptsSupport {
  _PromptNoisyServer(super.channel)
    : super.fromStreamChannel(
        implementation: Implementation(
          name: 'prompt noisy test server',
          version: '0.1.0',
        ),
      );

  @override
  FutureOr<void> initialize(MCPServerInitialization initialization) {
    registerTool(Tool(name: 'test/adds-prompt', inputSchema: ObjectSchema()), (
      _,
    ) {
      addPrompt(
        Prompt(name: 'added-while-answering'),
        (_) => GetPromptResult(messages: []),
      );
      return CallToolResult(content: [TextContent(text: 'added')]);
    });
    return super.initialize(initialization);
  }
}

/// A server which announces itself and then fails. The transport has already
/// committed the stream by the time the error reaches it.
base class _NoisyFailingServer extends _HttpTestServer {
  _NoisyFailingServer(super.channel);

  @override
  FutureOr<ServerCapabilities> initialize(
    MCPServerInitialization initialization,
  ) async {
    await super.initialize(initialization);
    sendNotification(
      LoggingMessageNotification.methodName,
      LoggingMessageNotification(
        level: LoggingLevel.error,
        data: 'while starting up',
      ),
    );
    throw StateError('initialize failed after announcing');
  }
}

/// A server which mixes in the support classes that register three of the
/// request handlers the 2026-07-28 revision removed, so a request for one of
/// them reaches a handler unless the transport turns it away first.
base class _EquippedServer extends MCPServer
    with ToolsSupport, LoggingSupport, ResourcesSupport {
  _EquippedServer(super.channel)
    : super.fromStreamChannel(
        implementation: Implementation(
          name: 'equipped test server',
          version: '0.1.0',
        ),
      );
}

Future<HttpServer> _integerHeaderServer(List<String?> headers) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final sent =
        jsonDecode(await utf8.decodeStream(request)) as Map<String, Object?>;
    if (sent[Keys.method] == listTools) {
      request.response
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            Keys.jsonrpc: '2.0',
            Keys.id: sent[Keys.id],
            Keys.result: {
              Keys.tools: [
                {
                  Keys.name: 'counted',
                  Keys.inputSchema: {
                    Keys.type: 'object',
                    Keys.properties: {
                      'count': {Keys.type: 'integer', Keys.xMcpHeader: 'Count'},
                    },
                  },
                },
              ],
            },
          }),
        );
    } else {
      headers.add(request.headers.value('Mcp-Param-Count'));
      request.response
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            Keys.jsonrpc: '2.0',
            Keys.id: sent[Keys.id],
            Keys.result: <String, Object?>{},
          }),
        );
    }
    await request.response.close();
  });
  return server;
}
