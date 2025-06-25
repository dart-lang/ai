// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:dart_mcp_server/src/mixins/analyzer.dart';
import 'package:dart_mcp_server/src/mixins/dash_cli.dart';
import 'package:dart_mcp_server/src/mixins/dtd.dart';
import 'package:dart_mcp_server/src/mixins/pub.dart';
import 'package:dart_mcp_server/src/mixins/pub_dev_search.dart';

final Map<String, List<Tool>> toolCategories = {
  'project': DashCliSupport.allTools,
  'analysis': DartAnalyzerSupport.allTools,
  'runtime': DartToolingDaemonSupport.allTools,
  'pub': PubSupport.allTools,
  'pub.dev': PubDevSupport.allTools,
};

void main(List<String> args) {
  final buf = StringBuffer();

  for (final entry in toolCategories.entries) {
    final category = entry.key;
    final tools = entry.value;

    buf.writeln('### $category');
    buf.writeln('');

    for (final tool in tools) {
      buf.writeln('- `${tool.name}`: ${tool.description}');
    }

    buf.writeln('');
  }

  final readmeFile = File('README.md');
  final updated = insertBetween(
    readmeFile.readAsStringSync(),
    buf.toString(),
    '<!-- generated -->',
  );
  readmeFile.writeAsStringSync(updated);
}

String insertBetween(String original, String insertion, String marker) {
  final startIndex = original.indexOf(marker) + marker.length;
  final endIndex = original.lastIndexOf(marker);

  return '${original.substring(0, startIndex)}\n\n'
      '$insertion${original.substring(endIndex)}';
}
