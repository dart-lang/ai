// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dart_mcp/server.dart';

/// A shared success response for tools.
final success = CallToolResult(content: [Content.text(text: 'Success')]);

/// Namespace for our custom scheme constants.
extension Schemes on Never {
  static const packageRoot = 'package-root';
  static const package = 'package';
}
