// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:async/async.dart';
import 'package:dart_mcp/server.dart';
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

  DartToolingMCPServer? server;
  await runZonedGuarded(
    () async {
      server = await DartToolingMCPServer.connect(
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
    },
    (e, s) {
      if (server != null) {
        try {
          // Log unhandled errors to the client, if we managed to connect.
          server!.log(LoggingLevel.error, '$e\n$s');
        } catch (_) {}
      } else {
        // Otherwise log to stderr.
        io.stderr
          ..writeln(e)
          ..writeln(s);
      }
    },
    zoneSpecification: ZoneSpecification(
      print: (_, _, _, value) {
        if (server != null) {
          try {
            // Don't allow `print` since this breaks stdio communication, but if
            // we have a server we do log messages to the client.
            server!.log(LoggingLevel.info, value);
          } catch (_) {}
        }
      },
    ),
  );
}
