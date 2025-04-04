// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io' as io;

import 'package:async/async.dart';
import 'package:dart_tooling_mcp_server/dart_tooling_mcp_server.dart';
import 'package:stream_channel/stream_channel.dart';

void main(List<String> args) async {
  if (args.isNotEmpty) {
    io.stderr
      ..writeln('Expected no arguments but got ${args.length}.')
      ..writeln()
      ..writeln('Usage: dart_tooling_mcp_server');
    io.exit(1);
  }

  await DartToolingMCPServer.connect(
    StreamChannel.withCloseGuarantee(io.stdin, io.stdout)
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
}
