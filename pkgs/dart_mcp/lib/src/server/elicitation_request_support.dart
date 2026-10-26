// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'server.dart';

/// A mixin that adds client capability checks and completion notifications for
/// elicitation to an [MCPServer].
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
  bool get supportsFormElicitation =>
      clientCapabilities.supportsFormElicitation;

  /// Whether or not the connected client supports [ElicitationMode.url]
  /// requests.
  ///
  /// Only safe to call after calling [initialize] on `super` since this
  /// is based on the client capabilities.
  bool get supportsUrlElicitation => clientCapabilities.supportsUrlElicitation;

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

  /// Notifies the client that a URL elicitation has completed.
  void notifyElicitationComplete(
    ElicitationCompleteNotification notification,
  ) => sendNotification(
    ElicitationCompleteNotification.methodName,
    notification,
  );
}
