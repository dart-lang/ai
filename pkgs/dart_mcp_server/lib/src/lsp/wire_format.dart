// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:async/async.dart';
import 'package:stream_channel/stream_channel.dart';

/// Handles LSP communication with its associated headers.
StreamChannel<String> lspChannel(
  Stream<List<int>> stream,
  StreamSink<List<int>> sink,
) {
  final parser = _Parser(stream);
  final outSink = StreamSinkTransformer.fromHandlers(
    handleData: _serialize,
    handleDone: (sink) {
      sink.close();
      parser.close();
    },
  ).bind(sink);
  return StreamChannel.withGuarantees(parser.stream, outSink);
}

/// Writes [data] to [sink], with the appropriate content length header.
///
/// Writes the [data] in 1KB chunks.
void _serialize(String data, EventSink<List<int>> sink) {
  final message = utf8.encode(data);
  final header = 'Content-Length: ${message.length}\r\n\r\n';
  sink.add(ascii.encode(header));
  for (var chunk in _chunks(message, 1024)) {
    sink.add(chunk);
  }
}

/// Parses content headers and the following messages.
///
/// Returns a [stream] of just the message contents.
class _Parser {
  /// Controller that gets a single [String] per entire
  /// JSON message received as input.
  final _messageController = StreamController<String>();

  /// Stream of full JSON messages in [String] form.
  Stream<String> get stream => _messageController.stream;

  /// All the input bytes for the message or header we are currently working
  /// with.
  final _buffer = <int>[];

  /// Whether or not we are still parsing the header.
  bool _headerMode = true;

  /// The parsed content length, or -1.
  int _contentLength = -1;

  /// The subscription for the input bytes stream.
  late final StreamSubscription _subscription;

  _Parser(Stream<List<int>> stream) {
    _subscription = stream
        .expand((bytes) => bytes)
        .listen(_handleByte, onDone: _messageController.close);
  }

  /// Shut down this parser.
  Future<void> close() => _subscription.cancel();

  /// Handles each incoming byte one at a time.
  void _handleByte(int byte) {
    _buffer.add(byte);
    if (_headerMode && _headerComplete) {
      _contentLength = _parseContentLength();
      _buffer.clear();
      _headerMode = false;
    } else if (!_headerMode && _messageComplete) {
      _messageController.add(utf8.decode(_buffer));
      _buffer.clear();
      _headerMode = true;
    }
  }

  /// Whether the entire message is in [_buffer].
  bool get _messageComplete => _buffer.length >= _contentLength;

  /// Decodes [_buffer] into a String and looks for the 'Content-Length' header.
  int _parseContentLength() {
    final asString = ascii.decode(_buffer);
    final headers = asString.split('\r\n');
    final lengthHeader = headers.firstWhere(
      (h) => h.startsWith('Content-Length'),
    );
    final length = lengthHeader.split(':').last.trim();
    return int.parse(length);
  }

  /// Whether [_buffer] ends in '\r\n\r\n'.
  bool get _headerComplete {
    final l = _buffer.length;
    return l > 4 &&
        _buffer[l - 1] == 10 &&
        _buffer[l - 2] == 13 &&
        _buffer[l - 3] == 10 &&
        _buffer[l - 4] == 13;
  }
}

/// Splits [data] into chunks of at most [chunkSize].
Iterable<List<T>> _chunks<T>(List<T> data, int chunkSize) sync* {
  if (data.length <= chunkSize) {
    yield data;
    return;
  }
  var low = 0;
  while (low < data.length) {
    if (data.length > low + chunkSize) {
      yield data.sublist(low, low + chunkSize);
    } else {
      yield data.sublist(low);
    }
    low += chunkSize;
  }
}
