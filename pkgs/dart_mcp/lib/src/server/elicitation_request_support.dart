// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'server.dart';

/// A mixin that adds support for making `elicitation/create` requests to a
/// [MCPServer].
base mixin ElicitationRequestSupport on LoggingSupport {
  /// Whether or not the connected client supports elicitation.
  ///
  /// Only safe to call after calling [initialize] on `super` since this
  /// is based on the client capabilities.
  bool get supportsElicitation => clientCapabilities.elicitation != null;

  /// Whether or not the connected client supports [ElicitationMode.form]
  /// requests.
  ///
  /// Only safe to call after calling [initialize] on `super` since this
  /// is based on the client capabilities.
  ///
  /// An empty `elicitation` object counts as form support, the backwards
  /// compatibility rule the 2025-11-25 revision added alongside the mode
  /// split. A client which named some other mode does not.
  bool get supportsFormElicitation {
    final elicitation = clientCapabilities.elicitation;
    if (elicitation == null) return false;
    return elicitation.form != null ||
        (elicitation as Map<String, Object?>).isEmpty;
  }

  /// Whether or not the connected client supports [ElicitationMode.url]
  /// requests.
  ///
  /// Only safe to call after calling [initialize] on `super` since this
  /// is based on the client capabilities.
  bool get supportsUrlElicitation =>
      clientCapabilities.elicitation?.url != null;

  @override
  FutureOr<void> initialize(MCPServerInitialization initialization) {
    initialized.then((_) {
      if (!supportsElicitation) {
        log(
          LoggingLevel.warning,
          'Client does not support the elicitation capability, some '
          'functionality may be disabled.',
        );
      }
    });
    return super.initialize(initialization);
  }

  /// Sends an `elicitation/create` request to the client.
  ///
  /// Throws an [RpcException] when [protocolVersion] does not have
  /// `elicitation/create`. 2026-07-28 took it out, and carries an
  /// [ElicitRequest] in an [InputRequiredResult] instead. 2025-06-18 is the
  /// revision which added it.
  ///
  /// On a revision which has it, this only succeeds if the client has
  /// advertised the mode the request asks for, as [supportsFormElicitation]
  /// and [supportsUrlElicitation] read it, and throws an [RpcException] with
  /// [McpErrorCodes.missingRequiredClientCapability] when the client has not,
  /// naming the capability it is missing under `data.requiredCapabilities`.
  ///
  /// [ToolsSupport.callTool] rethrows an [RpcException] instead of folding it
  /// into a [CallToolResult], so a tool which elicits reaches the client as
  /// that error rather than as a result whose text is a Dart stack trace.
  Future<ElicitResult> elicit(ElicitRequest request) async {
    _rejectRemovedMethod(ElicitRequest.methodName, protocolVersion);
    final raw = request.rawMode;
    if (raw != null && !ElicitationMode.values.any((m) => m.name == raw)) {
      throw RpcException.invalidParams(
        'The elicitation mode was "$raw", which is not one of: '
        '${ElicitationMode.values.map((m) => m.name).join(', ')}',
      );
    }
    switch (request.mode) {
      case ElicitationMode.url:
        if (!supportsUrlElicitation) {
          throw _missingClientCapability(
            'elicitation.url',
            ClientCapabilities(elicitation: ElicitationCapability(url: {})),
          );
        }
      case ElicitationMode.form:
        if (!supportsFormElicitation) {
          throw _missingClientCapability(
            'elicitation.form',
            ClientCapabilities(elicitation: ElicitationCapability(form: {})),
          );
        }
    }
    return sendRequest(ElicitRequest.methodName, request);
  }

  /// Notifies the client that a URL elicitation has completed.
  void notifyElicitationComplete(
    ElicitationCompleteNotification notification,
  ) => sendNotification(
    ElicitationCompleteNotification.methodName,
    notification,
  );
}
