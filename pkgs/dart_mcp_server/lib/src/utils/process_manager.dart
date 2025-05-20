// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:process/process.dart';

/// An interface class that provides a single getter of type
/// [LocalProcessManager].
///
/// The `DartMCPServer` class implements this class so that [Process]
/// methods can be easily mocked during testing.
///
/// MCP support mixins like `DartCliSupport` that spawn processes should also
/// implement this class and use [processManager] instead of making direct calls
/// to dart:io's [Process] class.
abstract interface class ProcessManagerSupport {
  LocalProcessManager get processManager;
}
