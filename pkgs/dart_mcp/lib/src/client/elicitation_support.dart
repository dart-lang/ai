// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'client.dart';

/// The interface for handling elicitation requests.
///
/// Any client using [ElicitationSupport] must implement this interface.
abstract interface class WithElicitationHandler {
  FutureOr<ElicitResult> handleElicitation(ElicitRequest request);
}

/// A mixin that adds support for the `elicitation` capability to an
/// [MCPClient].
base mixin ElicitationSupport on MCPClient implements WithElicitationHandler {
  @override
  void initialize() {
    capabilities.elicitation ??= ElicitationCapability();
    super.initialize();
  }
}
