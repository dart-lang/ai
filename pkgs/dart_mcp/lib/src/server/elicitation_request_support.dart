part of 'server.dart';

/// A mixin that adds support for making `elicitation/create` requests to a
/// [MCPServer].
base mixin ElicitationRequestSupport on LoggingSupport {
  /// Whether or not the connected client supports elicitation.
  ///
  /// Only safe to call after calling [initialize] on `super` since this
  /// is based on the client capabilities.
  bool get supportsElicitation => clientCapabilities.elicitation != null;

  @override
  FutureOr<ServerCapabilities> initialize(
    MCPServerInitialization initialization,
  ) {
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
  /// This method will only succeed if the client has advertised the
  /// `elicitation` capability.
  ///
  /// Throws an [RpcException] with
  /// [McpErrorCodes.missingRequiredClientCapability] when it has not, naming
  /// the capability the client is missing under `data.requiredCapabilities`,
  /// which the 2026-07-28 revision requires of that error.
  ///
  /// [ToolsSupport.callTool] rethrows an [RpcException] instead of folding it
  /// into a [CallToolResult], so a tool which elicits reaches the client as
  /// that error rather than as a result whose text is a Dart stack trace.
  Future<ElicitResult> elicit(ElicitRequest request) async {
    if (!supportsElicitation) {
      throw RpcException(
        McpErrorCodes.missingRequiredClientCapability,
        'The client did not declare the elicitation capability',
        data: {
          Keys.requiredCapabilities: ClientCapabilities(
            elicitation: ElicitationCapability(),
          ),
        },
      );
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
