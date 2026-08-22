// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'server.dart';

/// A mixin for MCP servers which support the `completion` capability.
///
/// See https://modelcontextprotocol.io/specification/2025-11-25/server/utilities/completion/.
base mixin CompletionsSupport on MCPServer {
  @override
  FutureOr<void> initialize(MCPServerInitialization initialization) async {
    registerRequestHandler(CompleteRequest.methodName, handleComplete);

    await super.initialize(initialization);
    capabilities.completions ??= Completions();
  }

  /// Handle a client request to provide completions.
  ///
  /// Must be implemented by the concrete server class.
  FutureOr<CompleteResult> handleComplete(CompleteRequest request);
}
