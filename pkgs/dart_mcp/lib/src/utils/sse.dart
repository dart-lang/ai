// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

/// Decodes the `message` events of a Streamable HTTP SSE response [bytes].
///
/// Consecutive `data` fields are joined with a line feed before the JSON
/// object is decoded. An omitted or empty `event` field means the `message`
/// type. Other event types, comment lines, and events carrying no data are
/// ignored.
///
/// A frame whose data does not decode to a JSON object arrives as a
/// [FormatException] error event. The frames behind it stay on the stream,
/// but `await for` cancels on the first error and will not reach them. An
/// error on [bytes] itself ends the stream, since there is nothing left to
/// read.
///
/// A frame cut short by the end of [bytes] is dropped. The event stream
/// interpretation rules ask for that, and for the UTF-8 decode algorithm,
/// which turns invalid bytes into the replacement character:
/// https://html.spec.whatwg.org/multipage/server-sent-events.html#event-stream-interpretation.
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
/// A line ends on CRLF, LF, or a bare CR and holds either a comment or a
/// field, as the event stream grammar has it:
/// https://html.spec.whatwg.org/multipage/server-sent-events.html#parsing-an-event-stream.
/// A field name cannot open with a colon. A line that does is a comment, and
/// is skipped before a field is read out of it. Servers send those to keep a
/// quiet stream alive.
///
/// The `id` and `retry` fields carry stream metadata, not payload: a last
/// event ID and a reconnection time. This revision has no resumable streams
/// to reconnect, and nothing here surfaces event metadata to a caller, so
/// neither field is read.
///
/// An event with no data has nothing to decode and never reaches the
/// stream.
///
/// `data` and `message` also spell MCP payload keys. Here they name SSE
/// framing, a separate namespace.
Stream<String> _sseMessageData(Stream<List<int>> bytes) async* {
  var event = '';
  final data = <String>[];
  await for (final line in const LineSplitter().bind(
    const Utf8Decoder(allowMalformed: true).bind(bytes),
  )) {
    if (line.isEmpty) {
      final source = data.join('\n');
      if (source.isNotEmpty && (event.isEmpty || event == 'message')) {
        yield source;
      }
      event = '';
      data.clear();
      continue;
    }

    if (line.startsWith(':')) continue;

    final separator = line.indexOf(':');
    final field = separator < 0 ? line : line.substring(0, separator);
    var value = separator < 0 ? '' : line.substring(separator + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    if (field == 'event') {
      event = value;
    } else if (field == 'data') {
      data.add(value);
    }
  }
}
