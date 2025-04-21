// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:process/process.dart';

/// A mixin that provides a single getter of type [LocalProcessManager].
///
/// The `DartToolingMCPServer` class mixes this in so that [Process] methods
/// can be easily mocked during testing.
///
/// MCP support mixins like `DartCliSupport` that spawn processes should use
/// [processManager] from this mixin instead of making direct calls to dart:io's
/// [Process] class.
mixin ProcessManagerSupport {
  LocalProcessManager get processManager;
}
