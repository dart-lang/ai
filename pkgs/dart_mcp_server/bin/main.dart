// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';
import 'package:dart_mcp_server/dart_mcp_server.dart';

void main(List<String> args) async {
  exitCode = await DartMCPServer.run(args);
}
