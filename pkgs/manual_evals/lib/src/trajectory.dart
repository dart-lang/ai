// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'sources/antigravity_runtime.dart';
import 'text.dart';
import 'transcript.dart';

/// What an agent did in one conversation, not including its subagents.
///
/// See [summarizeTrajectory].
final class Trajectory({
  /// The ID of the conversation.
  required final String conversationId,
  required Iterable<TrajectoryTurn> turns,
}) {
  /// The conversation's turns, in order.
  final List<TrajectoryTurn> turns = List.unmodifiable(turns);

  /// Every tool call in the conversation, in order.
  Iterable<TrajectoryToolCall> get toolCalls =>
      turns.expand((turn) => turn.toolCalls);
}

/// What an agent did in response to one user request.
final class TrajectoryTurn({
  /// The text of the user request that started the turn, on one line, or
  /// `null` for the steps before the first user request.
  required final String? request,

  /// For the steps before the first user request, the content of the first
  /// message the conversation received, on one line, if any.
  ///
  /// For a subagent, this is its assignment.
  final String? initialMessage,

  /// The time from the turn's earliest recorded step to its latest, or `null`
  /// if no step recorded a time.
  final Duration? duration,

  Iterable<ExplicitTrigger> triggers = const [],

  /// The first sentence of the model's first reasoning in the turn, if any.
  final String? thinking,

  /// The model's last message in the turn, on one line, if any.
  final String? reply,

  Iterable<TrajectoryToolCall> toolCalls = const [],
}) {
  /// The slash commands, skills, and other items the user explicitly
  /// triggered with the request, in order.
  final List<ExplicitTrigger> triggers = List.unmodifiable(triggers);

  /// The turn's tool calls, in order.
  final List<TrajectoryToolCall> toolCalls = List.unmodifiable(toolCalls);
}

/// How a tool call ended.
enum ToolCallOutcome {
  /// The call succeeded.
  succeeded,

  /// The call failed, couldn't be run, or ran a command that exited with a
  /// nonzero exit code.
  failed,

  /// The call has no final result, for example because it's still running or
  /// was canceled.
  unfinished,
}

/// A tool call made by an agent.
final class const TrajectoryToolCall({
  /// The name of the tool.
  ///
  /// Calls to MCP tools made through the runtime's MCP proxy tool are named
  /// `mcp_<server>_<tool>`, the way directly called MCP tools are.
  required final String tool,

  /// How the call ended.
  required final ToolCallOutcome outcome,

  /// The command line the call ran, if any.
  final String? command,

  /// The search query the call made, if any.
  final String? query,

  /// The file or directory the call acted on, if any.
  final String? path,

  /// The output of the call, without any header, if it
  /// [ToolCallOutcome.failed].
  final String? failureOutput,
}) {
  /// Whether this call may have modified the file at [path].
  ///
  /// This is true for calls to known file editing tools that didn't fail.
  bool get modifiesFile =>
      path != null &&
      outcome != ToolCallOutcome.failed &&
      fileEditingTools.contains(tool);
}

/// Summarizes what the agent did in [transcript], turn by turn.
///
/// A turn starts at each [StepType.userInput] step. The steps before the first
/// one form a turn without a request, which is left out if it has no model
/// calls.
///
/// Tool calls are matched to their results with [pairToolCalls]. A call fails
/// if it couldn't be run, its result has an error or the [StepStatus.error]
/// status or starts with `Error:`, or it ran a command that exited with a
/// nonzero exit code. The outcome of a call that ran in a background task
/// comes from the task's final result, reported in a later system message.
Trajectory summarizeTrajectory(ConversationTranscript transcript) {
  final callsByModelCall = Map<TranscriptStep, List<PairedToolCall>>.identity();
  for (final pair in pairToolCalls(transcript.steps)) {
    (callsByModelCall[pair.modelCall] ??= []).add(pair);
  }
  final taskResults = _taskResults(transcript.steps);

  TrajectoryTurn summarizeTurn(TranscriptTurn turn) {
    final modelCalls = [
      for (final step in turn.steps)
        if (step.type == StepType.plannerResponse) step,
    ];
    return TrajectoryTurn(
      request: turn.userInput?.userRequest,
      initialMessage: turn.userInput == null
          ? _firstMessageContent(turn.steps)
          : null,
      duration: _duration([for (final step in turn.steps) ?step.createdAt]),
      triggers: turn.userInput?.triggers ?? const [],
      thinking: modelCalls
          .map((step) => _firstSentence(step.thinking))
          .nonNulls
          .firstOrNull,
      reply: modelCalls
          .map((step) => oneLine(step.content))
          .where((message) => message.isNotEmpty)
          .lastOrNull,
      toolCalls: [
        for (final modelCall in modelCalls)
          for (final pair
              in callsByModelCall[modelCall] ?? const <PairedToolCall>[])
            _summarizeToolCall(pair, taskResults),
      ],
    );
  }

  return Trajectory(
    conversationId: transcript.conversationId,
    turns: splitTurns(transcript.steps).map(summarizeTurn),
  );
}

/// Returns the final results of the background tasks reported in the system
/// messages in [steps], by task ID.
Map<String, TaskResult> _taskResults(List<TranscriptStep> steps) => {
  for (final step in steps)
    if (step.type == StepType.systemMessage)
      for (final (:sender, :text) in runtimeMessages(step.content))
        sender: ?taskResult(text),
};

/// Returns the content of the first runtime message in [steps], on one line,
/// if any.
String? _firstMessageContent(List<TranscriptStep> steps) {
  for (final step in steps) {
    if (step.type != StepType.systemMessage) continue;
    for (final (sender: _, :text) in runtimeMessages(step.content)) {
      if (messageContent(text) case final content?) return oneLine(content);
    }
  }
  return null;
}

/// Returns the time from the earliest of [times] to the latest, or `null` if
/// there are none.
Duration? _duration(List<DateTime> times) {
  if (times.isEmpty) return null;
  final earliest = times.reduce((a, b) => b.isBefore(a) ? b : a);
  final latest = times.reduce((a, b) => b.isAfter(a) ? b : a);
  return latest.difference(earliest);
}

/// Returns the first sentence of [text], on one line, or `null` if [text] is
/// blank.
///
/// A sentence ends at a `.`, `!`, or `?` followed by whitespace and what looks
/// like the start of another sentence, so an abbreviation like "e.g."
/// followed by a lowercase word doesn't end one.
String? _firstSentence(String text) {
  final line = oneLine(text);
  return line.isEmpty ? null : line.split(_sentenceBreakPattern).first;
}

final _sentenceBreakPattern = RegExp(r'''(?<=[.!?])\s+(?=[A-Z0-9"'(\[`])''');

/// Summarizes the tool call in [pair], resolving the final results of calls
/// that ran in background tasks from [taskResults].
TrajectoryToolCall _summarizeToolCall(
  PairedToolCall pair,
  Map<String, TaskResult> taskResults,
) {
  final name = pair.toolName ?? unknownToolName;
  final arguments = _arguments(pair.call);
  final command = _stringArgument(arguments, commandArguments);
  final (:outcome, :failureOutput) = _resolve(
    pair.answer,
    ranCommand: command != null,
    taskResults: taskResults,
  );
  return TrajectoryToolCall(
    tool: switch ((name, arguments)) {
      (
        mcpProxyTool,
        {
          mcpServerArgument: final String server,
          mcpToolArgument: final String tool,
        },
      ) =>
        'mcp_${server}_$tool',
      _ => name,
    },
    outcome: outcome,
    command: command,
    query: _stringArgument(arguments, queryArguments),
    path: _stringArgument(arguments, pathArguments),
    failureOutput: failureOutput,
  );
}

/// Returns the arguments of the tool [call].
///
/// Abbreviated transcripts record the arguments JSON-encoded.
Map<String, Object?> _arguments(Object? call) {
  switch (call) {
    case {'args': final Map<String, Object?> arguments}:
      return arguments;
    case {'args': final String encoded}:
      try {
        if (jsonDecode(encoded) case final Map<String, Object?> arguments) {
          return arguments;
        }
      } on FormatException {
        // Treat malformed arguments as missing.
      }
  }
  return const {};
}

/// Returns the first non-empty string value in [arguments] of the arguments
/// named [names], if any.
String? _stringArgument(Map<String, Object?> arguments, List<String> names) {
  for (final name in names) {
    if (arguments[name] case final String value when value.isNotEmpty) {
      return value;
    }
  }
  return null;
}

/// How a tool call ended, and its output if it failed.
typedef _Resolution = ({ToolCallOutcome outcome, String? failureOutput});

const _Resolution _succeeded = (
  outcome: ToolCallOutcome.succeeded,
  failureOutput: null,
);

const _Resolution _unfinished = (
  outcome: ToolCallOutcome.unfinished,
  failureOutput: null,
);

/// The resolution of a call that failed with [result].
_Resolution _failed(String result) =>
    (outcome: ToolCallOutcome.failed, failureOutput: toolOutput(result));

/// Returns how a tool call answered by [answer] ended.
///
/// If the call [ranCommand], its result is also checked for the command's
/// exit code. If it ran in a background task, its final result is looked up
/// in [taskResults].
_Resolution _resolve(
  TranscriptStep? answer, {
  required bool ranCommand,
  required Map<String, TaskResult> taskResults,
}) {
  if (answer == null) return _unfinished;
  if (answer.type == StepType.errorMessage ||
      answer.status == StepStatus.error ||
      answer.error != null ||
      answer.content.startsWith(errorResultPrefix)) {
    return _failed(answer.error ?? answer.content);
  }

  if (backgroundTaskId(answer.content) case final taskId?) {
    return switch (taskResults[taskId]) {
      null || (end: TaskEnd.canceled, result: _) => _unfinished,
      (end: TaskEnd.failed, :final result) => _failed(result),
      (end: TaskEnd.finished, :final result) => _fromExitCode(
        ranCommand ? reportedExitCode(result) : null,
        result,
      ),
    };
  }

  final exitCode =
      answer.exitCode ?? (ranCommand ? reportedExitCode(answer.content) : null);
  if (exitCode != null) return _fromExitCode(exitCode, answer.content);
  // Results that don't record a status are taken to be complete.
  return switch (answer.status) {
    StepStatus.done || StepStatus.unrecorded => _succeeded,
    _ => _unfinished,
  };
}

/// The resolution of a call with [result] whose command exited with
/// [exitCode], which is `null` if the call didn't run a command.
_Resolution _fromExitCode(int? exitCode, String result) => switch (exitCode) {
  null || 0 => _succeeded,
  _ => _failed(result),
};
