// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library mcp_codegen;

import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import 'src/mcp_generator.dart';

Builder mcpBuilder(BuilderOptions options) {
  return PartBuilder([MCPGenerator()], '.mcp.g.dart');
}
