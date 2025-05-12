// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:file/file.dart';

/// An interface class that provides a single getter of type [FileSystem].
///
/// The `DartToolingMCPServer` class implements this class so that [File]
/// methods can be easily mocked during testing.
///
/// MCP support mixins like `DartCliSupport` that access files should also
/// implement this class and use [fileSystem] instead of making direct calls to
/// dart:io's [File] and [Directory] classes.
abstract interface class FileSystemSupport {
  FileSystem get fileSystem;
}
