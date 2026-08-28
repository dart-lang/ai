// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:dart_mcp/src/utils/sse.dart';
import 'package:test/test.dart';

void main() {
  /// The messages and the errors [sseMessageStream] delivers for [bytes],
  /// read to the end so that one error cannot hide the events behind it.
  Future<(List<Map<String, Object?>>, List<Object>)> decode(
    Stream<List<int>> bytes,
  ) async {
    final messages = <Map<String, Object?>>[];
    final errors = <Object>[];
    final done = Completer<void>();
    sseMessageStream(bytes).listen(
      messages.add,
      onError: errors.add,
      onDone: done.complete,
      cancelOnError: false,
    );
    await done.future;
    return (messages, errors);
  }

  test('decodes message events and skips comments', () async {
    final bytes = Stream.value(
      utf8.encode(
        ':\n'
        'event: message\n'
        'data: {"jsonrpc":"2.0","method":"notifications/message"}\n\n'
        'event: endpoint\n'
        'data: {"jsonrpc":"2.0","id":"ignored"}\n\n'
        'event: message\n'
        'data: {"jsonrpc":"2.0","id":1,"result":{}}\n\n',
      ),
    );
    final messages = await sseMessageStream(bytes).toList();

    expect(messages, [
      {'jsonrpc': '2.0', 'method': 'notifications/message'},
      {'jsonrpc': '2.0', 'id': 1, 'result': <String, Object?>{}},
    ]);
  });

  test('decodes a data line split across byte chunks', () async {
    final head = utf8.encode(
      'event: message\n'
      'data: {"jsonrpc":"2.0","id":1,"res',
    );
    final tail = utf8.encode('ult":{"value":"€"}}\n\n');
    // The second cut falls after the first of the three bytes of the euro
    // sign. Decoding a chunk on its own cannot put it back together.
    final cut = tail.indexOf(0xe2) + 1;
    final bytes = Stream.fromIterable([
      head,
      tail.sublist(0, cut),
      tail.sublist(cut),
    ]);
    final messages = await sseMessageStream(bytes).toList();

    expect(messages, [
      {
        'jsonrpc': '2.0',
        'id': 1,
        'result': {'value': '€'},
      },
    ]);
  });

  test('uses the default message event type', () async {
    final bytes = Stream.value(
      utf8.encode(
        'data: {"jsonrpc":"2.0","id":1,"result":{}}\n\n'
        'data: {"jsonrpc":"2.0","id":2,"result":{}}\n\n'
        'event:\n'
        'data: {"jsonrpc":"2.0","id":3,"result":{}}\n\n'
        'event: endpoint\n'
        'event\n'
        'data: {"jsonrpc":"2.0","id":4,"result":{}}\n\n',
      ),
    );

    expect(await sseMessageStream(bytes).toList(), [
      {'jsonrpc': '2.0', 'id': 1, 'result': <String, Object?>{}},
      {'jsonrpc': '2.0', 'id': 2, 'result': <String, Object?>{}},
      {'jsonrpc': '2.0', 'id': 3, 'result': <String, Object?>{}},
      {'jsonrpc': '2.0', 'id': 4, 'result': <String, Object?>{}},
    ]);
  });

  test('reads the event type of one frame only', () async {
    // The frame behind the endpoint one names no type. It is a message
    // event, and it is dropped if the endpoint type carries over.
    final messages =
        await sseMessageStream(
          Stream.value(
            utf8.encode(
              'event: endpoint\n'
              'data: {"jsonrpc":"2.0","id":"ignored"}\n\n'
              'data: {"jsonrpc":"2.0","id":1,"result":{}}\n\n',
            ),
          ),
        ).toList();

    expect(messages, [
      {'jsonrpc': '2.0', 'id': 1, 'result': <String, Object?>{}},
    ]);
  });

  test('joins consecutive data fields', () async {
    final bytes = Stream.value(
      utf8.encode(
        'event: message\n'
        'data: {"jsonrpc":"2.0",\n'
        'data: "id":1,"result":{}}\n\n'
        'data: {"jsonrpc":"2.0",\n'
        'data: "id":2,"result":{}}\n\n',
      ),
    );

    expect(await sseMessageStream(bytes).toList(), [
      {'jsonrpc': '2.0', 'id': 1, 'result': <String, Object?>{}},
      {'jsonrpc': '2.0', 'id': 2, 'result': <String, Object?>{}},
    ]);
  });

  test('preserves line feeds between data fields', () async {
    // Joining the two fields without the line feed would decode as a
    // `value` of 12, so the failure to decode is what proves it is kept.
    final (messages, errors) = await decode(
      Stream.value(
        utf8.encode(
          'data: {"jsonrpc":"2.0","id":1,"result":{"value":1\n'
          'data: 2}}\n\n',
        ),
      ),
    );

    expect(messages, isEmpty);
    expect(errors, [isFormatException]);
  });

  test('skips events with no data', () async {
    final (messages, errors) = await decode(
      Stream.value(
        utf8.encode(
          ': keep-alive\n\n'
          'data:\n\n'
          'data\n\n'
          'event: message\n\n'
          'data: {"jsonrpc":"2.0","id":1,"result":{}}\n\n',
        ),
      ),
    );

    expect(errors, isEmpty);
    expect(messages, [
      {'jsonrpc': '2.0', 'id': 1, 'result': <String, Object?>{}},
    ]);
  });

  test('keeps reading past invalid UTF-8', () async {
    final (messages, errors) = await decode(
      Stream<List<int>>.fromIterable([
        utf8.encode('data: {"jsonrpc":"2.0","id":1,"result":{}}\n\n'),
        [0xff], // never valid in UTF-8
        utf8.encode('\n\ndata: {"jsonrpc":"2.0","id":2,"result":{}}\n\n'),
      ]),
    );

    expect(errors, isEmpty);
    expect(messages, [
      {'jsonrpc': '2.0', 'id': 1, 'result': <String, Object?>{}},
      {'jsonrpc': '2.0', 'id': 2, 'result': <String, Object?>{}},
    ]);
  });

  test('drops the frame the response ends in the middle of', () async {
    // The response is cut off before the blank line that would end the second
    // frame, and half of a frame has no data worth handing on.
    final (messages, errors) = await decode(
      Stream.value(
        utf8.encode(
          'data: {"jsonrpc":"2.0","id":1,"result":{}}\n\n'
          'data: {"jsonrpc":"2.0","id":2,"res',
        ),
      ),
    );

    expect(messages, [
      {'jsonrpc': '2.0', 'id': 1, 'result': <String, Object?>{}},
    ]);
    expect(errors, isEmpty);
  });

  test('reports event data that is not a JSON object', () async {
    final (messages, errors) = await decode(
      Stream.value(utf8.encode('event: message\ndata: []\n\n')),
    );

    expect(messages, isEmpty);
    expect(errors, [
      // The message names the type it got, which the web compilers spell
      // differently, so the payload is what this pins down.
      isA<FormatException>()
          .having((error) => error.message, 'message', contains('JSON object'))
          .having((error) => error.source, 'source', '[]'),
    ]);
  });

  test('delivers the events after a frame fails to decode', () async {
    final (messages, errors) = await decode(
      Stream.value(
        utf8.encode(
          'data: {"jsonrpc":"2.0","id":1,"result":{}}\n\n'
          'data: {"jsonrpc":\n\n'
          'data: 7\n\n'
          'data: {"jsonrpc":"2.0","id":2,"result":{}}\n\n',
        ),
      ),
    );

    expect(messages, [
      {'jsonrpc': '2.0', 'id': 1, 'result': <String, Object?>{}},
      {'jsonrpc': '2.0', 'id': 2, 'result': <String, Object?>{}},
    ]);
    expect(errors, [isFormatException, isFormatException]);
  });

  test('ends the stream when the response fails', () async {
    final failure = StateError('connection reset');
    Stream<List<int>> response() async* {
      yield utf8.encode('data: {"jsonrpc":"2.0","id":1,"result":{}}\n\n');
      throw failure;
    }

    final (messages, errors) = await decode(response());

    expect(messages, [
      {'jsonrpc': '2.0', 'id': 1, 'result': <String, Object?>{}},
    ]);
    expect(errors, [same(failure)]);
  });
}
