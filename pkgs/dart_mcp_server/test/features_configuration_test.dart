// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Tests that all MCP tools/prompts have categories attached, that there are
/// no duplicate names, and that all tools/prompts are included in the
/// allFeatureAndCategoryNames list.
library;

import 'package:dart_mcp_server/src/arg_parser.dart';
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
import 'package:test/test.dart';

import 'test_harness.dart';

void main() {
  group('Features configuration', () {
    // Collect all tools and prompts from mixins
    final allTools = [
      ...DartAnalyzerSupport.allTools,
      ...DashCliSupport.allTools,
      ...DartToolingDaemonSupport.allTools,
      ...FlutterLauncherSupport.allTools,
      ...GrepSupport.allTools,
      ...PackageUriSupport.allTools,
      ...PubSupport.allTools,
      ...PubDevSupport.allTools,
      ...RootsFallbackSupport.allTools,
    ];

    final allPrompts = [...DashPrompts.allPrompts];

    test('All tools have categories', () {
      for (final tool in allTools) {
        expect(
          tool.categories,
          isNotEmpty,
          reason: 'Tool ${tool.name} should have at least one category',
        );
      }
    });

    test('All prompts have categories', () {
      for (final prompt in allPrompts) {
        expect(
          prompt.categories,
          isNotEmpty,
          reason: 'Prompt ${prompt.name} should have at least one category',
        );
      }
    });

    test('No overlapping names', () {
      final names = <String>{};
      for (final tool in allTools) {
        expect(
          names.add(tool.name),
          isTrue,
          reason: 'Duplicate tool name found: ${tool.name}',
        );
      }
      for (final prompt in allPrompts) {
        expect(
          names.add(prompt.name),
          isTrue,
          reason: 'Duplicate prompt name found: ${prompt.name}',
        );
      }
      for (final category in FeatureCategory.values) {
        expect(
          names.add(category.name),
          isTrue,
          reason: 'Duplicate category name found: ${category.name}',
        );
      }
    });

    test('arg_parser.allFeatureAndCategoryNames is complete', () {
      final expectedNames = {
        ...allTools.map((t) => t.name),
        ...allPrompts.map((p) => p.name),
        ...FeatureCategory.values.map((c) => c.name),
      };

      expect(allFeatureAndCategoryNames, containsAll(expectedNames));

      // Also check for extra names
      final extraNames = allFeatureAndCategoryNames.difference(expectedNames);
      expect(
        extraNames,
        isEmpty,
        reason: 'Found extra names in allFeatureAndCategoryNames: $extraNames',
      );
    });

    test('runtime validation with TestHarness', () async {
      final harness = await TestHarness.start(
        inProcess: true,
        forceRootsFallback: true,
      );

      final toolsResult = await harness.mcpServerConnection.listTools();
      final promptsResult = await harness.mcpServerConnection.listPrompts();

      final runtimeNames = {
        ...toolsResult.tools.map((t) => t.name),
        ...promptsResult.prompts.map((p) => p.name),
      };

      // Check that every runtime tool/prompt is covered in our static list
      expect(allFeatureAndCategoryNames, containsAll(runtimeNames));
    });
  });

  group('isEnabled', () {
    test('default is enabled', () {
      final config = FeaturesConfiguration();
      expect(config.isEnabled('foo', [FeatureCategory.cli]), isTrue);
    });

    test('disabled by name takes precedence over everything', () {
      final config = FeaturesConfiguration(
        disabledNames: {'foo'},
        enabledNames: {
          'foo',
          FeatureCategory.cli.name,
          FeatureCategory.all.name,
        },
      );
      expect(
        config.isEnabled('foo', [FeatureCategory.cli]),
        isFalse,
        reason: 'foo is disabled by name, which takes precedence over category',
      );
    });

    test('enabled by name takes precedence over category disable', () {
      final config = FeaturesConfiguration(
        enabledNames: {'foo'},
        disabledNames: {FeatureCategory.cli.name, FeatureCategory.all.name},
      );
      expect(
        config.isEnabled('foo', [FeatureCategory.cli]),
        isTrue,
        reason: 'foo is enabled by name, which takes precedence over category',
      );
    });

    test('child category takes precedence over parent category', () {
      var config = FeaturesConfiguration(
        disabledNames: {FeatureCategory.flutterDriver.name},
        enabledNames: {FeatureCategory.flutter.name},
      );
      expect(
        config.isEnabled('foo', [FeatureCategory.flutterDriver]),
        isFalse,
        reason: 'flutterDriver is disabled and higher category precedence',
      );

      config = FeaturesConfiguration(
        enabledNames: {FeatureCategory.flutterDriver.name},
        disabledNames: {FeatureCategory.flutter.name},
      );
      expect(
        config.isEnabled('foo', [FeatureCategory.flutterDriver]),
        isTrue,
        reason: 'flutterDriver is enabled and higher category precedence',
      );
    });

    test('category distance precedence in BFS order', () {
      var config = FeaturesConfiguration(
        disabledNames: {FeatureCategory.cli.name},
        enabledNames: {FeatureCategory.flutter.name},
      );
      expect(
        config.isEnabled('foo', [
          FeatureCategory.flutterDriver,
          FeatureCategory.cli,
        ]),
        isFalse,
        reason: 'cli is disabled and higher category precedence',
      );

      config = FeaturesConfiguration(
        enabledNames: {FeatureCategory.cli.name},
        disabledNames: {FeatureCategory.flutter.name},
      );
      expect(
        config.isEnabled('foo', [
          FeatureCategory.flutterDriver,
          FeatureCategory.cli,
        ]),
        isTrue,
        reason: 'cli is enabled and higher category precedence',
      );
    });

    test('order of input categories matters for same distance', () {
      var config = FeaturesConfiguration(
        disabledNames: {FeatureCategory.flutterDriver.name},
        enabledNames: {FeatureCategory.cli.name},
      );
      expect(
        config.isEnabled('foo', [
          FeatureCategory.flutterDriver,
          FeatureCategory.cli,
        ]),
        isFalse,
        reason: 'flutterDriver is disabled and higher category precedence',
      );

      config = FeaturesConfiguration(
        enabledNames: {FeatureCategory.flutterDriver.name},
        disabledNames: {FeatureCategory.cli.name},
      );
      expect(
        config.isEnabled('foo', [
          FeatureCategory.flutterDriver,
          FeatureCategory.cli,
        ]),
        isTrue,
        reason: 'flutterDriver is enabled and higher category precedence',
      );
    });

    test('parent category takes precedence over grandparent', () {
      var config = FeaturesConfiguration(
        disabledNames: {FeatureCategory.flutter.name},
        enabledNames: {FeatureCategory.all.name},
      );
      expect(
        config.isEnabled('foo', [FeatureCategory.flutterDriver]),
        isFalse,
        reason: 'flutter is disabled and higher category precedence',
      );

      config = FeaturesConfiguration(
        enabledNames: {FeatureCategory.flutter.name},
        disabledNames: {FeatureCategory.all.name},
      );
      expect(
        config.isEnabled('foo', [FeatureCategory.flutterDriver]),
        isTrue,
        reason: 'flutter is enabled and higher category precedence',
      );
    });

    test('categories are prioritized based on depth', () {
      var config = FeaturesConfiguration(
        disabledNames: {FeatureCategory.flutter.name},
        enabledNames: {FeatureCategory.all.name},
      );

      // all is encountered first, but flutterDriver is a child category
      // so it should be prioritized, including prioritizing its own parents
      // which are also children of `all` (flutter).
      expect(
        config.isEnabled('foo', [
          FeatureCategory.all,
          FeatureCategory.flutterDriver,
        ]),
        isFalse,
        reason:
            'flutterDriver config has higher precedence since it is a child of '
            '`all`, even though it is listed second',
      );

      config = FeaturesConfiguration(
        enabledNames: {FeatureCategory.flutter.name},
        disabledNames: {FeatureCategory.all.name},
      );
      expect(
        config.isEnabled('foo', [
          FeatureCategory.all,
          FeatureCategory.flutterDriver,
        ]),
        isTrue,
        reason:
            'flutterDriver config has higher precedence since it is a child of '
            '`all`, even though it is listed second',
      );
    });
  });
}
