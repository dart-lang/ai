// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:args/args.dart';

import 'arg_parser.dart';

/// The categories of features.
///
/// Features may have multiple categories.
enum FeatureCategory {
  /// Features for interacting with the Dart SDK and Dart projects.
  dart,

  /// Features for interacting with the Flutter SDK and Flutter projects.
  flutter,

  /// Features that require use of flutter_driver to interact with the app.
  flutterDriver,

  /// Features for interacting with the Dart Language Server.
  lsp,

  /// Features for interacting with the widget inspector.
  widgetInspector,

  /// Features which translate directly to a dart or flutter CLI command.
  cli,
}

/// Controls which features are enabled for a given configuration.
class FeaturesConfiguration {
  final Set<String> enabledNames;
  final Set<String> disabledNames;

  FeaturesConfiguration({
    this.enabledNames = const {},
    this.disabledNames = const {},
  });

  static FeaturesConfiguration fromArgs(ArgResults args) {
    return FeaturesConfiguration(
      enabledNames: args.multiOption(enabledFeaturesOption).toSet(),
      disabledNames: args.multiOption(disabledFeaturesOption).toSet(),
    );
  }

  /// Whether or not an MCP feature with [name] and [categories] should be
  /// enabled based on precedence rules.
  ///
  /// The precedence order is:
  ///
  ///   - Disabled by name
  ///   - Enabled by name
  ///   - Disabled by category
  ///   - Enabled by category
  bool isEnabled(String name, List<FeatureCategory> categories) {
    if (disabledNames.contains(name)) return false;
    if (enabledNames.contains(name)) return true;
    if (disabledNames.isNotEmpty &&
        categories.any((c) => disabledNames.contains(c.name))) {
      return false;
    }
    return enabledNames.isEmpty ||
        categories.any((c) => enabledNames.contains(c.name));
  }
}

/// Extension that allows for setting/getting categories for MCP feature
/// definitions via an expando.
///
/// These extension types do not have sensible shared subtypes so we have to
/// make this extension on [Object?].
extension Categorized on Object? {
  static final Expando<List<FeatureCategory>> _categories = Expando();

  List<FeatureCategory> get categories {
    assert(this is Map<String, Object?>);
    // Every tool should have categories set.
    assert(_categories[this as Object] != null);
    return _categories[this as Object] ?? <FeatureCategory>[];
  }

  set categories(List<FeatureCategory> value) {
    assert(this is Map<String, Object?>);
    // Categories should only get set once.
    assert(_categories[this as Object] == null);
    _categories[this as Object] = value;
  }
}
