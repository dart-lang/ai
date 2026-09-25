// Copyright (c) 2026, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'package:skills/src/commands/get_skills.dart';
import 'package:skills/src/core/dialog_support.dart';

/// A fake implementation of [DialogSupport] for testing.
class FakeDialogSupport implements DialogSupport {
  List<int?> singleSelectResults = [];
  int get singleSelectCallCount => _singleSelectCallCount;
  int _singleSelectCallCount = 0;

  // Canned selection optoins to return for dialogs.
  List<Set<int>?> multiSelectResults = [];
  // How many multi select dialogs have been seen.
  int _multiSelectCallCount = 0;

  // All the single select options ever given for dialogs in order.
  List<List<String>> lastSingleSelectOptions = [];

  // All the options ever given for dialogs in order.
  final List<List<String>> allMultiSelectOptions = [];
  // All the initial selected indices given for dialogs in order.
  final List<Set<int>> allInitialSelected = [];
  // All the titles given for dialogs in order.
  final List<String?> allTitles = [];

  // If `true`, then prompts for suggested repos will return an empty selection.
  final bool skipSuggestedRepos;

  FakeDialogSupport({this.skipSuggestedRepos = true});

  void reset() {
    _singleSelectCallCount = 0;
    _multiSelectCallCount = 0;
    multiSelectResults.clear();
    singleSelectResults.clear();
    allMultiSelectOptions.clear();
    allInitialSelected.clear();
    allTitles.clear();
    lastSingleSelectOptions.clear();
  }

  @override
  Future<int?> showSingleSelectDialog(
    List<String> options, {
    String? title,
  }) async {
    lastSingleSelectOptions.add(options);
    return singleSelectResults[_singleSelectCallCount++];
  }

  @override
  Future<Set<int>?> showMultiSelectDialog(
    List<String> options, {
    String? title,
    Set<int> initialSelected = const {},
  }) async {
    if (skipSuggestedRepos &&
        (title == installDartSkillsText ||
            title == installDartOrFlutterSkillsText)) {
      return const {};
    }

    allMultiSelectOptions.add(options);
    allInitialSelected.add(initialSelected);
    allTitles.add(title);

    return multiSelectResults[_multiSelectCallCount++];
  }
}

/// A fake implementation of [EnhancedDialogSupport] for testing.
///
/// Records option labels the same way as [FakeDialogSupport], and additionally
/// records the descriptions of all multi select options.
class FakeEnhancedDialogSupport extends FakeDialogSupport
    implements EnhancedDialogSupport {
  // All the descriptions given for recorded multi select dialogs in order,
  // parallel to [allMultiSelectOptions].
  final List<List<String?>> allMultiSelectDescriptions = [];

  FakeEnhancedDialogSupport({super.skipSuggestedRepos});

  @override
  void reset() {
    super.reset();
    allMultiSelectDescriptions.clear();
  }

  @override
  Future<int?> showEnhancedSingleSelectDialog(
    List<SelectOption> options, {
    String? title,
  }) =>
      showSingleSelectDialog([for (final o in options) o.label], title: title);

  @override
  Future<Set<int>?> showEnhancedMultiSelectDialog(
    List<SelectOption> options, {
    String? title,
    Set<int> initialSelected = const {},
  }) {
    final recordedCount = allMultiSelectOptions.length;
    final result = showMultiSelectDialog(
      [for (final o in options) o.label],
      title: title,
      initialSelected: initialSelected,
    );
    // Only record descriptions if the dialog was recorded (not skipped).
    if (allMultiSelectOptions.length > recordedCount) {
      allMultiSelectDescriptions.add([for (final o in options) o.description]);
    }
    return result;
  }
}
