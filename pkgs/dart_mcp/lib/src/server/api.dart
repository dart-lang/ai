// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:stream_channel/stream_channel.dart';
import 'package:json_rpc_2/json_rpc_2.dart';

abstract class MCPServer {
  late final Peer _peer;

  MCPServer.fromStreamChannel(StreamChannel<String> channel)
    : _peer = Peer(channel) {
    _peer.listen();
  }
}
