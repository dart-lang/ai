// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A server that tracks the client for roots with the [RootsTrackingSupport]
/// mixin and implements logging with the [LoggingSupport] mixin.
library;

import 'dart:async';
import 'dart:io' as io;

import 'package:dart_mcp/server.dart';
import 'package:dart_mcp/stdio.dart';

void main() {
  // Create the server and connect it to stdio.
  MCPServerWithRootsTrackingSupport(
    stdioChannel(input: io.stdin, output: io.stdout),
  );
}

/// Our actual MCP server.
///
/// This server uses the [LoggingSupport] and [RootsTrackingSupport] mixins to
/// receive root changes from the client and send log messages to it.
base class MCPServerWithRootsTrackingSupport extends MCPServer
    with LoggingSupport, RootsTrackingSupport {
  MCPServerWithRootsTrackingSupport(super.channel)
    : super.fromStreamChannel(
        implementation: Implementation(
          name: 'An example dart server with roots tracking support',
          version: '0.1.0',
        ),
        instructions: 'Just list and call the tools :D',
      ) {
    // Once the server is initialized, we can start listening for root changes
    // and printing the current roots.
    //
    // No communication is allowed prior to initialization, even logging.
    initialized.then((_) async {
      _logRoots();
      // Whenever the roots list changes, we log a message and print the new
      // roots.
      //
      // This stream is not set up until after initialization.
      rootsListChanged?.listen((_) {
        log(LoggingLevel.warning, 'Server got roots list change notification');
        _logRoots();
      });
    });
  }

  @override
  Future<InitializeResult> initialize(InitializeRequest request) async {
    // We require the client to support roots.
    if (request.capabilities.roots == null) {
      throw StateError('Client doesn\'t support roots!');
    }

    return await super.initialize(request);
  }

  /// Logs the current list of roots.
  void _logRoots() async {
    final initialRoots = await listRoots(ListRootsRequest());
    final rootsLines = initialRoots.roots
        .map((r) => '  - ${r.name}: ${r.uri}')
        .join('\n');
    log(
      LoggingLevel.warning,
      'Current roots:\n'
      '$rootsLines',
    );
  }
}
