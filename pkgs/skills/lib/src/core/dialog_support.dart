// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:io/ansi.dart' as ansi;

/// Interface for showing dialogs.
abstract interface class DialogSupport {
  /// Shows a single select dialog with the given [options].
  ///
  /// Returns the index of the selected option, or null if the dialog was
  /// cancelled or not implemented.
  ///
  /// The [title] will be shown in an implementation specific way if given.
  Future<int?> showSingleSelectDialog(List<String> options, {String? title});

  /// Shows a multi select dialog with the given [options].
  ///
  /// Returns the indices of the selected options, or null if the dialog was
  /// cancelled or not implemented.
  ///
  /// The [title] will be shown in an implementation specific way if given.
  ///
  /// If given, [initialSelected] are the initially selected indices.
  Future<Set<int>?> showMultiSelectDialog(
    List<String> options, {
    String? title,
    Set<int> initialSelected = const {},
  });
}

/// Formats [skillName] for display in CLI dialogs by emphasizing (bolding)
/// the actual skill name portion (the part after the package name or prefix).
///
/// For example:
/// - `formatSkillName('foo-bar', packageName: 'foo')` -> `'foo-'` + bold `'bar'`
/// - `formatSkillName('foo-bar-baz')` -> `'foo-'` + bold `'bar-baz'`
/// - `formatSkillName('simple')` -> bold `'simple'`
String formatSkillName(String skillName, {String? packageName}) {
  final prefix = _getSkillPrefix(skillName, packageName: packageName);
  if (prefix.isEmpty) {
    return ansi.styleBold.wrap(skillName) ?? skillName;
  }
  final rest = skillName.substring(prefix.length);
  final boldRest = ansi.styleBold.wrap(rest) ?? rest;
  return '$prefix$boldRest';
}

String _getSkillPrefix(String skillName, {String? packageName}) {
  if (packageName != null && packageName.isNotEmpty) {
    final pkgPrefix = '$packageName-';
    if (skillName.startsWith(pkgPrefix)) {
      return pkgPrefix;
    }
  }
  if (skillName.startsWith('flutter-')) {
    return 'flutter-';
  }
  if (skillName.startsWith('dart-')) {
    return 'dart-';
  }
  return '';
}
