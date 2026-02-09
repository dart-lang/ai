// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:args/args.dart';

import 'arg_parser.dart';

/// The categories of features.
///
/// Features may have multiple categories.
enum FeatureCategory {
  /// The highest level category, can be used to disable all features
  /// and then only enable the desired ones.
  all(null),

  /// Features for interacting with the Dart Language Server.
  analysis(all),

  /// Features which translate directly to a CLI command.
  cli(all),

  /// Features that are specific to Dart projects only.
  dart(all),

  /// Features that are specific to Flutter projects only.
  flutter(all),

  /// Features that require use of flutter_driver to interact with the app.
  flutterDriver(flutter),

  /// Features for interacting with the widget inspector.
  widgetInspector(flutter),

  /// Features for interacting with running apps via the Dart Tooling Daemon.
  dartToolingDaemon(all),

  /// Features for interacting with package dependencies, pub and/or pub.dev
  packageDeps(all);

  const FeatureCategory(this.parent);

  final FeatureCategory? parent;
}

/// Controls which features are enabled for a given configuration.
class FeaturesConfiguration {
  final Set<String> enabledNames;
  final Set<String> disabledNames;

  FeaturesConfiguration({
    this.enabledNames = const {'all'},
    this.disabledNames = const {},
  }) : // Enum names are not constant, we have to hard code it and then assert
       // the name is correct instead as a workaround.
       assert(FeatureCategory.all.name == 'all');

  static FeaturesConfiguration fromArgs(ArgResults args) {
    final disabled = args.multiOption(disabledFeaturesOption).toSet();
    if (args.option(toolsOption) == 'dart') {
      // This is the equivalent of the deprecated --tools=dart option,
      // just disable all flutter tools.
      disabled.add(FeatureCategory.flutter.name);
    }
    return FeaturesConfiguration(
      enabledNames: args.multiOption(enabledFeaturesOption).toSet()
        // We always enable `all`, this is the lowest precedence category.
        ..add(FeatureCategory.all.name),
      disabledNames: disabled,
    );
  }

  /// Whether or not an MCP feature with [name] and [categories] should be
  /// enabled based on precedence rules.
  ///
  /// The precedence order is:
  ///
  ///   - Disabled by name
  ///   - Enabled by name
  ///   - For each transitive category, in order of their category depth and
  ///     then their given order:
  ///     - Disabled by category
  ///     - Enabled by category
  bool isEnabled(String name, List<FeatureCategory> categories) {
    if (disabledNames.contains(name)) return false;
    if (enabledNames.contains(name)) return true;
    for (var category in _categoriesInPrecedenceOrder(categories)) {
      if (disabledNames.contains(category.name)) return false;
      if (enabledNames.contains(category.name)) return true;
    }
    // Should never reach here, this assert will get tripped up by tests.
    assert(false, 'Unreachable, should reach the `all` category');
    // If we do reach here in production, just return true (default is enabled).
    return true;
  }

  /// Returns all the transitive categories from a list of categories in
  /// precedence order.
  ///
  /// The precedence implementation is mostly a breadth first traversal of the
  /// [categories] and their transitive parents, but with the following rules:
  ///
  /// - More specific ("deeper") categories are higher precedence.
  /// - Earlier entries in [categories] are higher precedence than later
  ///   entries.
  /// - When parent categories are the same distance away, the ones whose
  ///   children were earlier in [categories] are higher precedence.
  Iterable<FeatureCategory> _categoriesInPrecedenceOrder(
    List<FeatureCategory> categories,
  ) sync* {
    final seen = <FeatureCategory>{...categories};
    final queue = <FeatureCategory>[];

    // Inserts `category` into queue ahead of any lower priority categories,
    // categories are prioritized based on their distance to the top level
    // category.
    void insert(FeatureCategory category) {
      final priority = distanceToTop(category);
      for (var i = 0; i < queue.length; i++) {
        final item = queue[i];
        if (distanceToTop(item) < priority) {
          queue.insert(i, category);
          return;
        }
      }
      queue.add(category);
      return;
    }

    categories.forEach(insert);
    while (queue.isNotEmpty) {
      final category = queue.removeAt(0);
      yield category;
      if (category.parent case final parent?) {
        if (seen.add(parent)) insert(parent);
      }
    }
  }

  /// Returns the distance from [category] to the top of its `parent`
  /// chain (ie: a `null` parent).
  int distanceToTop(FeatureCategory category) {
    var parent = category.parent;
    var result = 0;
    while (parent != null) {
      result++;
      parent = parent.parent;
    }
    return result;
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
    // Every tool should have at least one category (can be `all`).
    assert(value.isNotEmpty);
    _categories[this as Object] = value;
  }
}
