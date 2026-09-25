// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:io/ansi.dart' as ansi;

/// Interface for showing dialogs.
///
/// Implementations may also implement [EnhancedDialogSupport] to support
/// richer options (such as descriptions).
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

/// An option in an [EnhancedDialogSupport] dialog.
final class SelectOption {
  /// The main text displayed for this option.
  final String label;

  /// Additional details about this option, shown in an implementation
  /// specific way (for example, when the option is hovered).
  ///
  /// May contain newlines and ANSI SGR styling sequences.
  final String? description;

  const SelectOption(this.label, {this.description});
}

/// A [DialogSupport] which also supports richer [SelectOption]s.
///
/// Callers should check whether a [DialogSupport] is an
/// [EnhancedDialogSupport] and prefer these methods when it is.
abstract interface class EnhancedDialogSupport extends DialogSupport {
  /// Like [showSingleSelectDialog], but takes [SelectOption]s.
  Future<int?> showEnhancedSingleSelectDialog(
    List<SelectOption> options, {
    String? title,
  });

  /// Like [showMultiSelectDialog], but takes [SelectOption]s.
  Future<Set<int>?> showEnhancedMultiSelectDialog(
    List<SelectOption> options, {
    String? title,
    Set<int> initialSelected = const {},
  });
}

/// Helpers to show [SelectOption] dialogs on any [DialogSupport], falling back
/// to only the labels when it is not an [EnhancedDialogSupport].
extension SelectOptionDialogs on DialogSupport {
  /// Shows [EnhancedDialogSupport.showEnhancedSingleSelectDialog] if
  /// supported, otherwise [showSingleSelectDialog] with just the labels.
  Future<int?> showSingleSelectOptionsDialog(
    List<SelectOption> options, {
    String? title,
  }) => switch (this) {
    final EnhancedDialogSupport enhanced =>
      enhanced.showEnhancedSingleSelectDialog(options, title: title),
    _ => showSingleSelectDialog([
      for (final o in options) o.label,
    ], title: title),
  };

  /// Shows [EnhancedDialogSupport.showEnhancedMultiSelectDialog] if
  /// supported, otherwise [showMultiSelectDialog] with just the labels.
  Future<Set<int>?> showMultiSelectOptionsDialog(
    List<SelectOption> options, {
    String? title,
    Set<int> initialSelected = const {},
  }) => switch (this) {
    final EnhancedDialogSupport enhanced =>
      enhanced.showEnhancedMultiSelectDialog(
        options,
        title: title,
        initialSelected: initialSelected,
      ),
    _ => showMultiSelectDialog(
      [for (final o in options) o.label],
      title: title,
      initialSelected: initialSelected,
    ),
  };
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
