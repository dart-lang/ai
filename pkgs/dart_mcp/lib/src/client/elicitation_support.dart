// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'client.dart';

@Deprecated(
  'This interface is going away, the method will exist directly on the '
  'ElicitationSupport mixin instead',
)
abstract interface class WithElicitationHandler {
  FutureOr<ElicitResult> handleElicitation(ElicitRequest request);
}

/// A mixin that adds support for the `elicitation` capability to an
/// [MCPClient].
// ignore: deprecated_member_use_from_same_package
base mixin ElicitationSupport on MCPClient implements WithElicitationHandler {
  @override
  void initialize() {
    capabilities.elicitation ??= ElicitationCapability();
    super.initialize();
  }

  /// The method for handling elicitation requests.
  ///
  /// Any client using [ElicitationSupport] must implement this interface.
  @override
  FutureOr<ElicitResult> handleElicitation(ElicitRequest request);
}
