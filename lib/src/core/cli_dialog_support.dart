import 'dart:async';
import 'dart:io' as io;
import 'dart:math' as math;

import 'package:cli_util/cli_components.dart' as cli;
import 'package:io/io.dart';
import 'dialog_support.dart';

/// Implementation of [DialogSupport] using `package:cli_util` for basic CLI
/// integrations.
///
/// Assumes it can take full control of the terminal temporarily, can write to
/// stdout and is not compatible with many CLI frameworks that assert their own
/// control over the terminal window.
///
/// Also assumes [io.stdin] and [io.stdout] are connected to a terminal.
class CliUtilDialogSupport implements DialogSupport {
  // ignore: invalid_use_of_visible_for_testing_member
  final SharedStdIn _sharedStdIn;

  CliUtilDialogSupport(this._sharedStdIn);

  @override
  Future<int?> showSingleSelectDialog(List<String> options,
      {String? title}) async {
    if (title != null) io.stdout.writeln(title);
    final result = await cli.showSingleSelectDialog(
      options,
      _sharedStdIn,
      maxVisibleItems: _computeMaxVisibleItems(),
    );
    if (result != null) {
      io.stdout.writeln('> ${options[result]}');
    }
    return result;
  }

  @override
  Future<Set<int>?> showMultiSelectDialog(
    List<String> options, {
    String? title,
    Set<int> initialSelected = const {},
  }) async {
    if (title != null) io.stdout.writeln(title);
    final result = await cli.showMultiSelectDialog(
      options,
      _sharedStdIn,
      initialSelected: initialSelected,
      maxVisibleItems: _computeMaxVisibleItems(),
    );
    if (result != null) {
      final selectionStr =
          result.isEmpty ? 'None' : result.map((i) => options[i]).join(', ');
      io.stdout.writeln('> $selectionStr');
    }
    return result;
  }
}

/// Uses `stdout.terminalLines` when possible to fill up all vertical space,
/// with sensible defaults and minimums.
int _computeMaxVisibleItems() {
  if (!io.stdout.hasTerminal) return _defaultItems;
  try {
    // One extra line for the title, and one for padding at bottom, minimum 5.
    return math.max(io.stdout.terminalLines - 2, _minItems);
  } on io.StdoutException {
    return _defaultItems;
  }
}

/// Constants for dialog configuration.
const _minItems = 5;
const _defaultItems = 10;
