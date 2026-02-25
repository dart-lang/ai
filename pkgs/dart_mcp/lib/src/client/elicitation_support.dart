// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'client.dart';

@Deprecated('Use ElicitationFormSupport or ElicitationUrlSupport instead')
typedef ElicitationSupport = ElicitationFormSupport;

/// A shared interface for both [ElicitationFormSupport] and
/// [ElicitationUrlSupport].
abstract interface class _WithElicitationHandler {
  /// Clients must implement this function, which will be called whenever
  /// the [connection] sends an elicitation [request].
  FutureOr<ElicitResult> handleElicitation(
    ElicitRequest request,
    ServerConnection connection,
  );
}

/// A mixin that adds support for the `elicitation.forms` capability to an
/// [MCPClient], and will delegate all such calls to [handleElicitation].
base mixin ElicitationFormSupport on MCPClient
    implements _WithElicitationHandler {
  @override
  void initialize() {
    final capability = capabilities.elicitation ??= ElicitationCapability();
    capability.form ??= {};
    super.initialize();
  }
}

/// A mixin that adds support for the `elicitation.urls` capability to an
/// [MCPClient], and will delegate all such calls to [handleElicitation].
base mixin ElicitationUrlSupport on MCPClient
    implements _WithElicitationHandler {
  /// Whether or not tool calls which fail due to a `urlElicitationRequired`
  /// error should be automatically retried after a successful elicitation
  /// using the provided URL.
  ///
  /// This requires servers to send elicitation complete notifications or else
  /// the tool call will never complete.
  bool get autoHandleUrlElicitationRequired => true;

  @override
  void initialize() {
    final capability = capabilities.elicitation ??= ElicitationCapability();
    capability.url ??= {};
    super.initialize();
  }
}
