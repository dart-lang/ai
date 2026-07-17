// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:async/async.dart';
import 'package:dart_mcp/server.dart';
import 'package:dart_mcp/src/utils/constants.dart';
import 'package:dart_mcp/stdio.dart';
import 'package:json_rpc_2/error_code.dart' as error_code;
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  group('jsonRpcChannel', () {
    test('decodes json objects and encodes them back', () async {
      final harness = _EdgeHarness();
      harness.wireIn.add(
        jsonEncode({Keys.jsonrpc: '2.0', Keys.method: 'notifications/test'}),
      );
      await pumpEventQueue();
      expect(harness.received.single[Keys.method], 'notifications/test');

      harness.channel.sink.add({Keys.jsonrpc: '2.0', Keys.id: 1});
      expect(jsonDecode(await harness.wire.next), {
        Keys.jsonrpc: '2.0',
        Keys.id: 1,
      });
    });

    test('answers invalid json with a parse error', () async {
      final harness = _EdgeHarness();
      harness.wireIn.add('Just some random text');

      final response = await harness.nextWireObject();
      expect(response[Keys.id], isNull);
      final error = _error(response);
      expect(error[Keys.code], error_code.PARSE_ERROR);
      expect(error[Keys.message], contains('Invalid JSON'));
    });

    test('answers a frame which is not a json object', () async {
      final harness = _EdgeHarness();
      harness.wireIn.add('42');

      final response = await harness.nextWireObject();
      expect(response[Keys.id], isNull);
      final error = _error(response);
      expect(error[Keys.code], error_code.INVALID_REQUEST);
      expect(error[Keys.message], contains('must be a JSON object'));
    });

    test('answers a batch frame with an invalid request error', () async {
      final harness = _EdgeHarness();
      harness.wireIn.add(
        jsonEncode([
          {
            Keys.jsonrpc: '2.0',
            Keys.id: 1,
            Keys.method: PingRequest.methodName,
          },
        ]),
      );

      final response = await harness.nextWireObject();
      expect(response[Keys.id], isNull);
      final error = _error(response);
      expect(error[Keys.code], error_code.INVALID_REQUEST);
      expect(error[Keys.message], contains('Batch messages are not supported'));
    });

    test('a server survives invalid frames', () async {
      final harness = _EdgeHarness(drain: false);
      final server = TestMCPServer(harness.channel);
      addTearDown(server.shutdown);

      harness.wireIn.add('Just some random text');
      final parseError = _error(await harness.nextWireObject());
      expect(parseError[Keys.code], error_code.PARSE_ERROR);

      harness.wireIn.add(
        jsonEncode({
          Keys.jsonrpc: '2.0',
          Keys.id: 1,
          Keys.method: InitializeRequest.methodName,
          Keys.params: {
            Keys.protocolVersion: ProtocolVersion.latestSupported.versionString,
            Keys.capabilities: <String, Object?>{},
            Keys.clientInfo: {Keys.name: 'test client', Keys.version: '0.1'},
          },
        }),
      );
      final response = await harness.nextWireObject();
      expect(response[Keys.id], 1);
      expect(response.containsKey(Keys.result), isTrue);
    });

    test('a client survives invalid frames', () async {
      final harness = _EdgeHarness(drain: false);
      final client = TestMCPClient();
      addTearDown(client.shutdown);
      final connection = client.connectServer(harness.channel);

      harness.wireIn.add('Just some random text');
      final parseError = _error(await harness.nextWireObject());
      expect(parseError[Keys.code], error_code.PARSE_ERROR);

      final initializeDone = connection.initialize(
        InitializeRequest(
          protocolVersion: ProtocolVersion.latestSupported,
          capabilities: client.capabilities,
          clientInfo: client.implementation,
        ),
      );
      final request = await harness.nextWireObject();
      expect(request[Keys.method], InitializeRequest.methodName);
      harness.wireIn.add(
        jsonEncode({
          Keys.jsonrpc: '2.0',
          Keys.id: request[Keys.id],
          Keys.result: {
            Keys.protocolVersion: ProtocolVersion.latestSupported.versionString,
            Keys.capabilities: <String, Object?>{},
            Keys.serverInfo: {Keys.name: 'test server', Keys.version: '0.1'},
          },
        }),
      );
      final result = await initializeDone;
      expect(result.serverInfo.name, 'test server');
    });
  });

  group('stdioChannel', () {
    test('speaks newline delimited json over bytes', () async {
      final input = StreamController<List<int>>();
      final output = StreamController<List<int>>();
      final channel = stdioChannel(input: input.stream, output: output.sink);

      input.add(utf8.encode('{"jsonrpc":"2.0","method":"a"}\n'));
      expect((await channel.stream.first)[Keys.method], 'a');

      channel.sink.add({Keys.jsonrpc: '2.0', Keys.id: 2});
      final line = utf8.decode(await output.stream.first);
      expect(line, endsWith('\n'));
      expect(jsonDecode(line), {Keys.jsonrpc: '2.0', Keys.id: 2});
    });
  });
}

/// A [jsonRpcChannel] over an in-memory pair of string controllers.
///
/// The decoded messages are collected into [received] unless `drain` is
/// false, in which case the caller owns the stream (for example by handing
/// [channel] to a server). Wire output is read through [wire] or
/// [nextWireObject].
final class _EdgeHarness {
  _EdgeHarness({bool drain = true}) {
    addTearDown(close);
    if (drain) channel.stream.listen(received.add);
  }

  final wireIn = StreamController<String>();
  final wireOut = StreamController<String>();
  final received = <Map<String, Object?>>[];

  late final channel = jsonRpcChannel(
    StreamChannel.withCloseGuarantee(wireIn.stream, wireOut.sink),
  );

  late final wire = StreamQueue(wireOut.stream);

  /// Reads the next wire frame and decodes it as a JSON object.
  Future<Map<String, Object?>> nextWireObject() async =>
      (jsonDecode(await wire.next) as Map).cast<String, Object?>();

  void close() {
    unawaited(wireIn.close());
    unawaited(wireOut.close());
    unawaited(wire.cancel(immediate: true));
  }
}

Map<String, Object?> _error(Object? response) =>
    ((response as Map)[Keys.error] as Map).cast<String, Object?>();
