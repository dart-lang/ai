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
import 'package:dart_mcp_server/src/mixins/prompts.dart';
import 'package:dart_mcp_server/src/mixins/pub.dart';
import 'package:dart_mcp_server/src/mixins/pub_dev_search.dart';
import 'package:dart_mcp_server/src/mixins/roots_fallback_support.dart';
import 'package:dart_mcp_server/src/utils/names.dart';

void main(List<String> args) async {
  print('Getting registered tools...');

  final tools = _registeredTools();
  tools.sortBy((tool) => tool.name);

  final buf = StringBuffer('''
| Tool Name | Title | Description | Categories | Enabled by default |
| --- | --- | --- | --- | --- |
''');
  for (final tool in tools) {
    final categories = tool.categories
        .where((c) => c != FeatureCategory.all)
        .map((c) => c.name)
        .join(', ');
    buf.writeln(
      '| `${tool.name}` | ${tool.displayName} | '
      '${tool.description?.replaceAll('\n', '<br>') ?? ''} | '
      '${categories.isEmpty ? 'None' : categories} | '
      '${tool.enabledByDefault ? 'Yes' : 'No'} |',
    );
  }

  print('Getting registered prompts...');

  final prompts = _registeredPrompts();
  prompts.sortBy((prompt) => prompt.name);

  final promptsBuf = StringBuffer('''
| Prompt Name | Title | Description | Arguments | Categories | Enabled by default |
| --- | --- | --- | --- | --- | --- |
''');
  for (final prompt in prompts) {
    final arguments = [
      for (final argument in prompt.arguments ?? const <PromptArgument>[])
        [
          '`${argument.name}`',
          if (argument.required != true) ' (optional)',
          if (argument.description case final description?) ': $description',
        ].join(),
    ];
    final categories = prompt.categories
        .where((c) => c != FeatureCategory.all)
        .map((c) => c.name)
        .join(', ');
    promptsBuf.writeln(
      '| `${prompt.name}` | ${prompt.title ?? ''} | '
      // Prompt descriptions are wrapped for readability in the source, but a
      // table cell must be a single line.
      '${prompt.description?.trim().replaceAll('\n', ' ') ?? ''} | '
      '${arguments.isEmpty ? 'None' : arguments.join('<br>')} | '
      '${categories.isEmpty ? 'None' : categories} | '
      '${prompt.enabledByDefault ? 'Yes' : 'No'} |',
    );
  }

  final readmeFile = File('README.md');
  var updated = _insertBetween(
    readmeFile.readAsStringSync(),
    buf.toString(),
    '<!-- generated -->',
  );
  updated = _insertBetween(
    updated,
    promptsBuf.toString(),
    '<!-- generated prompts -->',
  );
  readmeFile.writeAsStringSync(updated);

  print('Wrote updated tool and prompt lists to ${readmeFile.path}.');
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

List<Prompt> _registeredPrompts() {
  final allPrompts = <Prompt>[...DashPrompts.allPrompts];

  // Ensure that we don't miss any prompts when updating the README.
  final allPromptNames = PromptNames.values.map((p) => p.name).toSet();
  final difference = allPromptNames.difference(
    allPrompts.map((p) => p.name).toSet(),
  );
  if (difference.isNotEmpty) {
    throw StateError(
      'The list of prompts is missing the following prompts: $difference',
    );
  }

  return allPrompts;
}

extension on Tool {
  String get displayName => toolAnnotations?.title ?? '';
}
