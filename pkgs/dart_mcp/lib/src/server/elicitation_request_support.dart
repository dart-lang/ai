part of 'server.dart';

/// A mixin that adds support for making `elicitation/create` requests to a
/// [MCPClient].
base mixin ElicitationRequestSupport on LoggingSupport {
  /// Whether or not the connected client supports elicitation.
  ///
  /// Only safe to call after calling [initialize] on `super` since this is
  /// based on the client capabilities.
  bool get supportsElicitation => clientCapabilities.elicitation != null;

  @override
  FutureOr<InitializeResult> initialize(InitializeRequest request) {
    initialized.then((_) async {
      if (!supportsElicitation) {
        log(
          LoggingLevel.warning,
          'Client does not support the elicitation capability, some '
          'functionality may be disabled.',
        );
      }
    });
    return super.initialize(request);
  }

  /// Sends an `elicitation/create` request to the client.
  ///
  /// This method will only success if the client has advertised the
  /// `elicitation` capability.
  Future<ElicitationResult> elicit(String message, Schema requestedSchema) {
    if (!supportsElicitation) {
      throw StateError('Client does not support elicitation');
    }
    return sendRequest(
      ElicitationRequest.methodName,
      ElicitationRequest(message: message, requestedSchema: requestedSchema),
    );
  }
}
