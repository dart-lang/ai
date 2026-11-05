// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:dart_mcp_server/dart_mcp_server.dart';
import 'package:unified_analytics/unified_analytics.dart';

void main(List<String> args) async {
  // The MCP server is a shared component, so it reports itself as the tool
  // (recorded as `leaf_tool`). unified_analytics resolves the root tool from
  // the `DASH__TOOL` environment variable, and disables analytics if it isn't
  // set to a tool that can be a root tool.
  final analytics = Analytics(
    tool: DashTool.dartMcpServer,
    dartVersion: parseDartSDKVersion(Platform.version),
  );

  try {
    exitCode = await DartMCPServer.run(args, analytics: analytics);
  } finally {
    await analytics.close();
  }
}
