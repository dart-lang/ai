// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Checks that this package still understands an agent's transcripts.
///
/// Run it from inside an agent, ideally in a conversation with subagents:
///
/// ```sh
/// dart run tool/check_transcript_format.dart [--all] [conversation-id]
/// ```
///
/// Without an ID, it checks the current conversation. It prints at most 20
/// problems unless `--all` is given, and exits with a non-zero code if the
/// transcripts can't be read or weren't fully understood.
library;

import 'dart:io';

import 'package:args/args.dart';
import 'package:manual_evals/manual_evals.dart';

Future<void> main(List<String> args) async {
  final loaded = await loadConversationTreeFromArgs(
    args,
    usage:
        'Usage: dart run tool/check_transcript_format.dart [options] '
        '[conversation-id]',
    parser: ArgParser()
      ..addFlag(
        'all',
        negatable: false,
        help: 'Print every problem, not just the first $_maxProblems.',
      ),
  );
  if (loaded == null) return;
  final (:tree, :options) = loaded;
  final showAll = options.flag('all');

  for (final transcript in tree.transcripts) {
    final modelCalls = transcript.steps
        .where((step) => step.type == StepType.plannerResponse)
        .length;
    stdout.writeln(
      '${transcript.conversationId}: '
      '${_count(transcript.steps.length, 'step')}, '
      '${_count(modelCalls, 'model call')}, '
      '${_count(transcript.subagentIds.length, 'subagent')}',
    );
  }
  if (tree.root.subagentIds.isEmpty) {
    stdout.writeln(
      '\nNote: no subagents were found, so subagent detection was not checked.',
    );
  }

  final problems = checkTranscriptFormat(tree);
  if (problems.isEmpty) {
    stdout.writeln('\nOK: all transcripts were understood.');
    return;
  }
  stdout.writeln('\n${_count(problems.length, 'problem')} found:');
  final shown = showAll ? problems : problems.take(_maxProblems);
  for (final problem in shown) {
    stdout.writeln('- $problem');
  }
  if (!showAll && problems.length > _maxProblems) {
    stdout.writeln(
      '- ...and ${problems.length - _maxProblems} more. Use --all to see them.',
    );
  }
  exitCode = 1;
}

/// The maximum number of problems to print without `--all`.
const _maxProblems = 20;

String _count(int count, String noun) => '$count $noun${count == 1 ? '' : 's'}';
