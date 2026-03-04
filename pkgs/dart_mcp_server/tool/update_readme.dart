// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:io';

import 'package:collection/collection.dart';
import 'package:dart_mcp/client.dart';
import 'package:dart_mcp_server/src/features_configuration.dart';
import 'package:dart_mcp_server/src/mixins/analyzer.dart';
import 'package:dart_mcp_server/src/mixins/dash_cli.dart';
import 'package:dart_mcp_server/src/mixins/dtd.dart';
import 'package:dart_mcp_server/src/mixins/flutter_launcher.dart';
import 'package:dart_mcp_server/src/mixins/grep_packages.dart';
import 'package:dart_mcp_server/src/mixins/package_uri_reader.dart';
import 'package:dart_mcp_server/src/mixins/pub.dart';
import 'package:dart_mcp_server/src/mixins/pub_dev_search.dart';
import 'package:dart_mcp_server/src/mixins/roots_fallback_support.dart';
import 'package:dart_mcp_server/src/utils/names.dart';

void main(List<String> args) async {
  print('Getting registered tools...');

  final tools = _registeredTools();
  tools.sortBy((tool) => tool.name);

  final buf = StringBuffer('''
| Tool Name | Title | Description | Categories | Enabled |
| --- | --- | --- | --- | --- |
''');
  for (final tool in tools) {
    final categories = tool.categories
        .where((c) => c != FeatureCategory.all)
        .map((c) => c.name)
        .join(', ');
    buf.writeln(
      '| `${tool.name}` | ${tool.displayName} | ${tool.description} | '
      '${categories.isEmpty ? 'None' : categories} | '
      '${tool.enabledByDefault ? 'Yes' : 'No'} |',
    );
  }

  final readmeFile = File('README.md');
  final updated = _insertBetween(
    readmeFile.readAsStringSync(),
    buf.toString(),
    '<!-- generated -->',
  );
  readmeFile.writeAsStringSync(updated);

  print('Wrote update tool list to ${readmeFile.path}.');
}

String _insertBetween(String original, String insertion, String marker) {
  final startIndex = original.indexOf(marker) + marker.length;
  final endIndex = original.lastIndexOf(marker);

  return '${original.substring(0, startIndex)}\n\n'
      '$insertion\n${original.substring(endIndex)}';
}

List<Tool> _registeredTools() {
  final allTools = <Tool>[
    ...DartAnalyzerSupport.allTools,
    ...DartToolingDaemonSupport.allTools,
    ...DashCliSupport.allTools,
    ...FlutterLauncherSupport.allTools,
    ...GrepSupport.allTools,
    ...RootsFallbackSupport.allTools,
    ...PackageUriSupport.allTools,
    ...PubSupport.allTools,
    ...PubDevSupport.allTools,
  ];

  // Ensure that we don't miss any tools when updating the README.
  final allToolNames = ToolNames.values.map((t) => t.name).toSet();
  final difference = allToolNames.difference(
    allTools.map((t) => t.name).toSet(),
  );
  if (difference.isNotEmpty) {
    throw StateError(
      'The list of tools is missing the following tools: $difference',
    );
  }

  return allTools;
}

extension on Tool {
  String get displayName => toolAnnotations?.title ?? '';
}
