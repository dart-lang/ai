// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'client.dart';

/// Adds support for "sampling" to an [MCPClient].
///
/// See https://spec.modelcontextprotocol.io/specification/2024-11-05/client/sampling/.
base mixin SamplingSupport on MCPClient {
  @override
  void initialize() {
    capabilities.sampling ??= {};
    super.initialize();
  }

  /// Handles a request to prompt the LLM from the server.
  ///
  /// Must be implemented by clients. According to spec, the client should
  /// request approval from a human before sending this prompt to the LLM,
  /// as well as before sending the response back to the server.
  ///
  /// See https://spec.modelcontextprotocol.io/specification/2024-11-05/client/sampling/#message-flow
  ///
  /// The [serverInfo] is the description that the server initiating this
  /// request gave when it was initialized.
  FutureOr<CreateMessageResult> handleCreateMessage(
    CreateMessageRequest request,
    ServerImplementation serverInfo,
  );
}
