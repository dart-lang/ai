// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Prints a Markdown report of the token usage of a conversation and its
/// subagents.
///
/// ```sh
/// dart run scripts/token_usage.dart [conversation-id]
/// ```
///
/// Without an ID, it reports on the current conversation.
library;

import 'dart:io';

import 'package:manual_evals/manual_evals.dart';

Future<void> main(List<String> args) async {
  final loaded = await loadConversationTreeFromArgs(
    args,
    usage: 'Usage: dart run scripts/token_usage.dart [conversation-id]',
  );
  if (loaded == null) return;
  stdout.write(formatTokenReport(loaded.tree));
}
