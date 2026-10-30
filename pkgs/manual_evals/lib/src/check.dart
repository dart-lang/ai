// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'transcript.dart';

/// Returns the problems that suggest the transcripts in [tree] weren't fully
/// understood.
///
/// Transcripts are read leniently, so this is how to detect changes to an
/// agent's transcript format. Run it on a real conversation, ideally one with
/// subagents.
///
/// The problems are [ConversationTree.warnings], followed by:
///
/// - Transcripts with steps but no [StepType.plannerResponse] steps.
/// - Model calls without exactly one result per tool call (see
///   [pairToolResults]). The last model call in a transcript may still be
///   running, so it is only checked for extra results.
/// - No model call in the tree recording token usage.
List<TranscriptWarning> checkTranscriptFormat(ConversationTree tree) => [
  ...tree.warnings,
  for (final transcript in tree.transcripts) ..._checkTranscript(transcript),
  if (!tree.transcripts.any(
    (transcript) => transcript.steps.any(_recordsTokenUsage),
  ))
    TranscriptWarning(
      tree.root.conversationId,
      'No model call in the conversation or its subagents recorded token '
      'usage.',
    ),
];

Iterable<TranscriptWarning> _checkTranscript(
  ConversationTranscript transcript,
) sync* {
  final id = transcript.conversationId;
  if (transcript.steps.isEmpty) return;
  if (!transcript.steps.any((step) => step.type == StepType.plannerResponse)) {
    yield TranscriptWarning(id, 'No PLANNER_RESPONSE steps.');
    return;
  }

  final calls = _ModelCall.all(transcript.steps).toList();
  for (final (index, call) in calls.indexed) {
    final isLast = index == calls.length - 1;
    if (call.resultCount > call.toolCallCount ||
        (call.resultCount < call.toolCallCount && !isLast)) {
      yield TranscriptWarning(
        id,
        'Found ${_count(call.resultCount, 'tool result')} for '
        '${_count(call.toolCallCount, 'tool call')}.',
        stepIndex: call.stepIndex,
      );
    }
  }
}

String _count(int count, String noun) => '$count $noun${count == 1 ? '' : 's'}';

bool _recordsTokenUsage(TranscriptStep step) =>
    step.type == StepType.plannerResponse &&
    (step.inputTokens != null || step.outputTokens != null);

/// A model call and the number of tool results that follow it.
final class _ModelCall {
  final int? stepIndex;
  final int toolCallCount;
  int resultCount = 0;

  _ModelCall(TranscriptStep step)
    : stepIndex = step.stepIndex,
      toolCallCount = step.toolCallNames.length;

  /// Returns the model calls in [steps], counting results the way
  /// [pairToolResults] pairs them, except that results beyond a call's tool
  /// calls are counted too, so that they can be reported.
  static Iterable<_ModelCall> all(List<TranscriptStep> steps) sync* {
    _ModelCall? current;
    for (final step in steps) {
      if (step.type == StepType.plannerResponse) {
        if (current != null) yield current;
        current = _ModelCall(step);
      } else if (current != null &&
          (step.isToolResult ||
              (step.type == StepType.errorMessage &&
                  current.resultCount < current.toolCallCount))) {
        current.resultCount++;
      }
    }
    if (current != null) yield current;
  }
}
