// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:async/async.dart';
import 'package:stream_channel/stream_channel.dart';

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

void _serialize(String data, EventSink<List<int>> sink) {
  final message = utf8.encode(data);
  final header = 'Content-Length: ${message.length}\r\n\r\n';
  sink.add(ascii.encode(header));
  for (var chunk in _chunks(message, 1024)) {
    sink.add(chunk);
  }
}

class _Parser {
  final _streamCtl = StreamController<String>();
  Stream<String> get stream => _streamCtl.stream;

  final _buffer = <int>[];
  bool _headerMode = true;
  int _contentLength = -1;

  late final StreamSubscription _subscription;

  _Parser(Stream<List<int>> stream) {
    _subscription = stream
        .expand((bytes) => bytes)
        .listen(_handleByte, onDone: _streamCtl.close);
  }

  Future<void> close() => _subscription.cancel();

  void _handleByte(int byte) {
    _buffer.add(byte);
    if (_headerMode && _headerComplete) {
      _contentLength = _parseContentLength();
      _buffer.clear();
      _headerMode = false;
    } else if (!_headerMode && _messageComplete) {
      _streamCtl.add(utf8.decode(_buffer));
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
