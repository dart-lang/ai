// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'constants.dart';

/// Decodes the `message` events in a Streamable HTTP SSE response [bytes].
///
/// Consecutive `data` fields are joined with a line feed before the JSON
/// object is decoded. An omitted or empty `event` field means the `message`
/// type. Other event types, comment lines, and events which carry no data are
/// ignored.
///
/// A frame whose data does not decode to a JSON object arrives as a
/// [FormatException] error event, and the frames behind it are still
/// delivered. An error on [bytes] itself ends the stream, since there is
/// nothing left to read.
///
/// Bytes that are not valid UTF-8 become the replacement character instead of
/// an error.
Stream<Map<String, Object?>> sseMessageStream(Stream<List<int>> bytes) =>
    _sseMessageData(bytes).map<Map<String, Object?>>((source) {
      final decoded = jsonDecode(source);
      if (decoded is! Map<String, Object?>) {
        throw FormatException(
          'SSE data must be a JSON object, got ${decoded.runtimeType}',
          source,
        );
      }
      return decoded;
    });

/// The joined `data` of each `message` event in an SSE response [bytes].
///
/// An event with no data has nothing to decode, so it never reaches the
/// stream.
Stream<String> _sseMessageData(Stream<List<int>> bytes) async* {
  var event = '';
  final data = <String>[];
  await for (final line in const LineSplitter().bind(
    const Utf8Decoder(allowMalformed: true).bind(bytes),
  )) {
    if (line.isEmpty) {
      final source = data.join('\n');
      if (source.isNotEmpty && (event.isEmpty || event == Keys.message)) {
        yield source;
      }
      event = '';
      data.clear();
      continue;
    }

    final separator = line.indexOf(':');
    final field = separator < 0 ? line : line.substring(0, separator);
    var value = separator < 0 ? '' : line.substring(separator + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    if (field == 'event') {
      event = value;
    } else if (field == Keys.data) {
      data.add(value);
    }
  }
}
