part of 'client.dart';

/// A function that can handle an elicitation request.
typedef ElicitationHandler =
    FutureOr<ElicitResult> Function(ElicitRequest request);

/// A mixin that adds support for the `elicitation` capability to an
/// [MCPClient].
base mixin ElicitationSupport on MCPClient {
  ElicitationHandler? _elicitationHandler;

  /// The handler for elicitation requests.
  ///
  /// If this is not null, it will receive any elicitation requests from the
  /// server.
  ///
  /// If it is null, all elicitation requests will be rejected.
  ElicitationHandler? get elicitationHandler => _elicitationHandler;
  set elicitationHandler(ElicitationHandler? handler) {
    _elicitationHandler = handler;
  }

  @override
  void initialize() {
    capabilities.elicitation ??= ElicitationCapability();
    super.initialize();
  }
}
