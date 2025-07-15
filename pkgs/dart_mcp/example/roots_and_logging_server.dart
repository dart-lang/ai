// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io' as io;

import 'package:dart_mcp/server.dart';
import 'package:dart_mcp/stdio.dart';

void main() {
  MCPServerWithRootsTrackingSupport(
    stdioChannel(input: io.stdin, output: io.stdout),
  );
}

/// Our actual MCP server.
base class MCPServerWithRootsTrackingSupport extends MCPServer
    with LoggingSupport, RootsTrackingSupport {
  MCPServerWithRootsTrackingSupport(super.channel)
    : super.fromStreamChannel(
        implementation: Implementation(
          name: 'An example dart server with roots tracking support',
          version: '0.1.0',
        ),
        instructions: 'Just list and call the tools :D',
      );

  @override
  Future<InitializeResult> initialize(InitializeRequest request) async {
    unawaited(
      initialized.then((_) async {
        _printRoots();
        rootsListChanged?.listen((_) {
          log(
            LoggingLevel.warning,
            'Server got roots list change notification',
          );
          _printRoots();
        });
      }),
    );

    if (request.capabilities.roots == null) {
      throw StateError('Client doesn\'t support roots!');
    }

    return await super.initialize(request);
  }

  void _printRoots() async {
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
