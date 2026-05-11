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
  Future<int?> showSingleSelectDialog(List<String> options, {String? title}) {
    if (title != null) io.stdout.writeln(title);
    return cli.showSingleSelectDialog(options, _sharedStdIn);
  }

  @override
  Future<Set<int>?> showMultiSelectDialog(List<String> options,
      {String? title}) {
    if (title != null) io.stdout.writeln(title);
    return cli.showMultiSelectDialog(options, _sharedStdIn);
  }
}
