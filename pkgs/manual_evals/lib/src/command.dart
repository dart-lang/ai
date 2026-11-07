// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:args/args.dart';

import 'loading.dart';
import 'transcript.dart';

/// Loads the conversation tree that a command-line tool reports on, from the
/// tool's command-line [args].
///
/// [args] may contain a conversation ID, `-h` or `--help`, and the options of
/// [parser], which must not define `help`. Without an ID, the current
/// conversation is used.
///
/// Returns the tree and the parsed [args], or `null` if the tool should stop:
/// after printing the usage for `--help`, or after printing a message to
/// stderr and setting [exitCode] if [args] are invalid or the tree can't be
/// loaded. The usage is [usage] followed by the help for each option.
Future<({ConversationTree tree, ArgResults options})?>
loadConversationTreeFromArgs(
  List<String> args, {
  required String usage,
  ArgParser? parser,
}) async {
  // This parses [args] itself, rather than taking `ArgResults`, so that parse
  // errors are reported in one place, and so that skill scripts without
  // options of their own don't need to depend on `package:args`.
  final argParser = (parser ?? ArgParser())
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Print this usage information.',
    );
  final fullUsage = '$usage\n\n${argParser.usage}';

  void usageError(String message) {
    stderr
      ..writeln(message)
      ..writeln()
      ..writeln(fullUsage);
    exitCode = 64;
  }

  final ArgResults options;
  try {
    options = argParser.parse(args);
  } on FormatException catch (e) {
    usageError(e.message);
    return null;
  }
  if (options.flag('help')) {
    stdout.writeln(fullUsage);
    return null;
  }
  if (options.rest.length > 1) {
    usageError('Expected at most one conversation ID: ${options.rest}');
    return null;
  }

  final conversationId = resolveConversationId(options.rest.firstOrNull);
  if (conversationId == null) {
    stderr.writeln(
      'No conversation ID given, and no current conversation detected.',
    );
    exitCode = 64;
    return null;
  }

  try {
    return (tree: await loadConversationTree(conversationId), options: options);
  } on TranscriptNotFoundException catch (e) {
    stderr.writeln(e);
  } on FileSystemException catch (e) {
    stderr.writeln("Can't read the transcript of $conversationId: $e");
  }
  exitCode = 1;
  return null;
}
