// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:async/async.dart';
import 'package:stream_channel/stream_channel.dart';

/// Creates a [StreamChannel] for Stdio communication where messages are
/// separated by newlines.
///
/// This expects incoming messages on [input], and writes messages to [output].
StreamChannel<String> stdioChannel({
  required Stream<List<int>> input,
  required StreamSink<List<int>> output,
}) => StreamChannel.withCloseGuarantee(input, output)
    .transform(StreamChannelTransformer.fromCodec(utf8))
    .transformStream(const LineSplitter())
    .transformSink(
      StreamSinkTransformer.fromHandlers(
        handleData: (data, sink) {
          sink.add('$data\n');
        },
      ),
    );
