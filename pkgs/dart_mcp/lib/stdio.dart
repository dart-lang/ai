// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:async/async.dart';
import 'package:json_rpc_2/error_code.dart' as error_code;
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:stream_channel/stream_channel.dart';

/// Creates a [StreamChannel] for Stdio communication where each message is a
/// map, encoded as JSON on its own line.
///
/// This expects incoming messages on [input], and writes messages to [output].
/// Frames which are not JSON objects are answered with JSON-RPC error
/// responses and never surface on the channel; see [jsonRpcChannel].
StreamChannel<Map<String, Object?>> stdioChannel({
  required Stream<List<int>> input,
  required StreamSink<List<int>> output,
}) => jsonRpcChannel(
  StreamChannel.withCloseGuarantee(input, output)
      .transform(StreamChannelTransformer.fromCodec(utf8))
      .transformStream(const LineSplitter())
      .transformSink(
        StreamSinkTransformer.fromHandlers(
          handleData: (data, sink) {
            sink.add('$data\n');
          },
        ),
      ),
);

/// Adapts a channel of JSON strings into a channel of decoded JSON-RPC
/// messages.
///
/// Each event on [channel] must contain one complete JSON document; this
/// helper does not provide framing.
///
/// Frames which are not valid JSON, or which decode to something other than a
/// JSON object, are answered on [channel] with a JSON-RPC error response and
/// never surface on the returned channel. This includes JSON-RPC batch
/// frames, which MCP removed in protocol version 2025-06-18.
StreamChannel<Map<String, Object?>> jsonRpcChannel(
  StreamChannel<String> channel,
) {
  void answer(int code, String message, Object? request) {
    channel.sink.add(
      jsonEncode(RpcException(code, message).serialize(request)),
    );
  }

  final stream =
      channel.stream
          .map<Object?>(jsonDecode)
          .handleError((Object error) {
            final formatException = error as FormatException;
            answer(
              error_code.PARSE_ERROR,
              'Invalid JSON: ${formatException.message}',
              formatException.source,
            );
          }, test: (error) => error is FormatException)
          .where((message) {
            if (message is Map<String, Object?>) return true;
            answer(
              error_code.INVALID_REQUEST,
              message is List
                  ? 'Batch messages are not supported. Batching was removed '
                      'in MCP protocol version 2025-06-18.'
                  : 'Message must be a JSON object.',
              message,
            );
            return false;
          })
          .cast<Map<String, Object?>>();
  final sink = StreamSinkTransformer<Map<String, Object?>, String>.fromHandlers(
    handleData: (data, sink) {
      sink.add(jsonEncode(data));
    },
  ).bind(channel.sink);
  return StreamChannel.withCloseGuarantee(stream, sink);
}
