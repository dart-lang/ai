import 'dart:async';
import 'dart:io' as io;

import 'package:cli_util/cli_components.dart' as cli;
import 'package:io/io.dart';
import 'dialog_support.dart';

/// Implementation of [EnhancedDialogSupport] using `package:cli_util` for
/// basic CLI integrations.
///
/// Assumes it can take full control of the terminal temporarily, can write to
/// stdout and is not compatible with many CLI frameworks that assert their own
/// control over the terminal window.
///
/// Also assumes [io.stdin] and [io.stdout] are connected to a terminal.
class CliUtilDialogSupport implements EnhancedDialogSupport {
  // ignore: invalid_use_of_visible_for_testing_member
  final SharedStdIn _sharedStdIn;

  CliUtilDialogSupport(this._sharedStdIn);

  @override
  Future<int?> showSingleSelectDialog(List<String> options, {String? title}) =>
      showEnhancedSingleSelectDialog([
        for (final o in options) SelectOption(o),
      ], title: title);

  @override
  Future<Set<int>?> showMultiSelectDialog(
    List<String> options, {
    String? title,
    Set<int> initialSelected = const {},
  }) => showEnhancedMultiSelectDialog(
    [for (final o in options) SelectOption(o)],
    title: title,
    initialSelected: initialSelected,
  );

  @override
  Future<int?> showEnhancedSingleSelectDialog(
    List<SelectOption> options, {
    String? title,
  }) async {
    if (title != null) io.stdout.writeln(title);
    final result = await cli.showSingleSelectDialog(
      _toCliOptions(options),
      _sharedStdIn,
      sizing: _sizing,
    );
    if (result != null) {
      io.stdout.writeln('> ${options[result].label}');
    }
    return result;
  }

  @override
  Future<Set<int>?> showEnhancedMultiSelectDialog(
    List<SelectOption> options, {
    String? title,
    Set<int> initialSelected = const {},
  }) async {
    if (title != null) io.stdout.writeln(title);
    final result = await cli.showMultiSelectDialog(
      _toCliOptions(options),
      _sharedStdIn,
      initialSelected: initialSelected,
      sizing: _sizing,
    );
    if (result != null) {
      final selectionStr = result.isEmpty
          ? 'None'
          : result.map((i) => options[i].label).join(', ');
      io.stdout.writeln('> $selectionStr');
    }
    return result;
  }
}

List<cli.SelectOption> _toCliOptions(List<SelectOption> options) => [
  for (final o in options)
    cli.SelectOption(o.label, description: o.description),
];

/// Fills up all available vertical space in the terminal, and allows
/// descriptions to take up to half of that space.
const _sizing = cli.SelectComponentSizing.fit();
