// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io' as io;

import 'package:stream_channel/stream_channel.dart';

import 'api.dart';

/// Creates a new [MCPServer] that communicates over stdin/stdout.
///
/// This should be used for local servers which run as a subprocess of a client.
class StdIOMCPServer extends MCPServer {
  StdIOMCPServer()
    : super.fromStreamChannel(
        StreamChannel(io.stdin, io.stdout)
            .transform(StreamChannelTransformer.fromCodec(utf8))
            .transformStream(const LineSplitter()),
      );
}
