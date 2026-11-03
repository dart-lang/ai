// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'loading.dart';
import 'transcript.dart';

/// Loads the conversation tree that a command-line tool reports on, from the
/// tool's command-line [args].
///
/// [args] may contain a conversation ID and any of [flags]. Without an ID, the
/// current conversation is used.
///
/// Returns `null` if the tool should stop, after printing [usage] for `-h` or
/// `--help`, or a message to stderr and setting [exitCode] if [args] are
/// invalid or the tree can't be loaded.
Future<ConversationTree?> loadConversationTreeFromArgs(
  List<String> args, {
  required String usage,
  Set<String> flags = const {},
}) async {
  if (args.contains('-h') || args.contains('--help')) {
    stdout.writeln(usage);
    return null;
  }
  final ids = [
    for (final arg in args)
      if (!arg.startsWith('-')) arg,
  ];
  final unknownFlags = [
    for (final arg in args)
      if (arg.startsWith('-') && !flags.contains(arg)) arg,
  ];
  if (ids.length > 1 || unknownFlags.isNotEmpty) {
    stderr.writeln(usage);
    exitCode = 64;
    return null;
  }

  final conversationId = resolveConversationId(ids.firstOrNull);
  if (conversationId == null) {
    stderr.writeln(
      'No conversation ID given, and no current conversation detected.',
    );
    exitCode = 64;
    return null;
  }

  try {
    return await loadConversationTree(conversationId);
  } on TranscriptNotFoundException catch (e) {
    stderr.writeln(e);
  } on FileSystemException catch (e) {
    stderr.writeln("Can't read the transcript of $conversationId: $e");
  }
  exitCode = 1;
  return null;
}
