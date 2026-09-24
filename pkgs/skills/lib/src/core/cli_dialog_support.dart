import 'dart:async';
import 'dart:io' as io;

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
  Future<int?> showSingleSelectDialog(
    List<String> options, {
    String? title,
    List<String?>? descriptions,
  }) async {
    if (title != null) io.stdout.writeln(title);
    final result = await cli.showSingleSelectDialog(
      _selectOptions(options, descriptions),
      _sharedStdIn,
      sizing: _sizing,
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
    List<String?>? descriptions,
  }) async {
    if (title != null) io.stdout.writeln(title);
    final result = await cli.showMultiSelectDialog(
      _selectOptions(options, descriptions),
      _sharedStdIn,
      initialSelected: initialSelected,
      sizing: _sizing,
    );
    if (result != null) {
      final selectionStr = result.isEmpty
          ? 'None'
          : result.map((i) => options[i]).join(', ');
      io.stdout.writeln('> $selectionStr');
    }
    return result;
  }
}

/// Combines [labels] and optional [descriptions] into [cli.SelectOption]s.
List<cli.SelectOption> _selectOptions(
  List<String> labels,
  List<String?>? descriptions,
) {
  if (descriptions != null && descriptions.length != labels.length) {
    throw ArgumentError.value(
      descriptions,
      'descriptions',
      'Must have the same length as options (${labels.length})',
    );
  }
  return [
    for (var i = 0; i < labels.length; i++)
      cli.SelectOption(labels[i], description: descriptions?[i]),
  ];
}

/// Fills up all available vertical space in the terminal, and allows
/// descriptions to take up to half of that space.
const _sizing = cli.SelectComponentSizing.fit();
