// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:args/args.dart';

import 'features_configuration.dart';
import 'utils/names.dart';

/// All features that can be enabled/disabled by name or category in the MCP
/// server.
final allFeatureAndCategoryNames = <String>{
  ...ToolNames.values.map((e) => e.name),
  ...PromptNames.values.map((e) => e.name),
  ...FeatureCategory.values.map((e) => e.name),
};

/// Creates an arg parser for th MCP server.
///
/// The `--help` option is only included if [includeHelp] is `true`.
///
/// Passing no options results in the default arg parser.
ArgParser createArgParser({
  bool includeHelp = true,
  bool allowTrailingOptions = false,
  int? usageLineLength,
}) {
  final parser =
      ArgParser(
          allowTrailingOptions: allowTrailingOptions,
          usageLineLength: usageLineLength,
        )
        ..addOption(
          dartSdkOption,
          help:
              'The path to the root of the desired Dart SDK. Defaults to the '
              'DART_SDK environment variable.',
        )
        ..addOption(
          flutterSdkOption,
          help:
              'The path to the root of the desired Flutter SDK. Defaults to '
              'the FLUTTER_SDK environment variable, then searching up from '
              'the Dart SDK.',
        )
        ..addFlag(
          forceRootsFallbackFlag,
          negatable: true,
          defaultsTo: false,
          help:
              'Forces a behavior for project roots which uses MCP tools '
              'instead of the native MCP roots. This can be helpful for '
              'clients like Cursor which claim to have roots support but do '
              'not actually support it.',
        )
        ..addOption(
          logFileOption,
          help:
              'Path to a file to log all MPC protocol traffic to. File will be '
              'overwritten if it exists.',
        )
        ..addMultiOption(
          disabledFeaturesOption,
          aliases: ['exclude-tool'],
          abbr: 'x',
          help:
              'The names or categories of features to disable. Disabled '
              'features by name take precedence over enabled features by name '
              'and category, and disabled features by category take precedence '
              'over enabled features by category, but not name.',
          allowed: allFeatureAndCategoryNames,
        )
        ..addMultiOption(
          enabledFeaturesOption,
          aliases: ['tools'],
          help:
              'The names or categories of features to enable, defaults to all '
              'features. If any value is passed, only those features will be '
              'enabled.',
          allowed: allFeatureAndCategoryNames,
          defaultsTo: [FeatureCategory.all.name],
        );

  if (includeHelp) parser.addFlag(helpFlag, abbr: 'h', help: 'Show usage text');
  return parser;
}

const dartSdkOption = 'dart-sdk';
const disabledFeaturesOption = 'disable';
const enabledFeaturesOption = 'enable';
const flutterSdkOption = 'flutter-sdk';
const forceRootsFallbackFlag = 'force-roots-fallback';
const helpFlag = 'help';
const logFileOption = 'log-file';
