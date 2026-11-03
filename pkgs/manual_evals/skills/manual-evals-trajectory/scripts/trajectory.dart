// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Prints a Markdown report of what a conversation and its subagents did,
/// turn by turn.
///
/// ```sh
/// dart run scripts/trajectory.dart [conversation-id]
/// ```
///
/// Without an ID, it reports on the current conversation.
library;

import 'dart:io';

import 'package:manual_evals/manual_evals.dart';

Future<void> main(List<String> args) async {
  final tree = await loadConversationTreeFromArgs(
    args,
    usage: 'Usage: dart run scripts/trajectory.dart [conversation-id]',
  );
  if (tree == null) return;
  stdout.write(formatTrajectoryReport(tree));
}
