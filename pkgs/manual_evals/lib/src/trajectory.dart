// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'text.dart';
import 'transcript.dart';

/// What an agent did in one conversation, not including its subagents.
final class Trajectory({
  /// The ID of the conversation.
  required final String conversationId,
  required List<TrajectoryTurn> turns,
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

  /// The time from the turn's first recorded step to its last, or `null` if
  /// no step recorded a time.
  final Duration? duration,

  required List<TurnTrigger> triggers,

  /// The first sentence of the model's first reasoning in the turn, if any.
  final String? thinking,

  /// The model's last message in the turn, on one line, if any.
  final String? reply,

  required List<TrajectoryToolCall> toolCalls,
}) {
  /// The slash commands, skills, and other items the user explicitly
  /// triggered with the request, in order.
  final List<TurnTrigger> triggers = List.unmodifiable(triggers);

  /// The turn's tool calls, in order.
  final List<TrajectoryToolCall> toolCalls = List.unmodifiable(toolCalls);
}

/// A slash command, skill, or other item that a user explicitly triggered,
/// such as `(kind: 'Slash Command', name: '/plan')`.
typedef TurnTrigger = ({String kind, String name});

/// How a tool call ended.
enum ToolOutcome {
  /// The call succeeded.
  succeeded,

  /// The call failed, couldn't be run, or ran a command that exited with a
  /// nonzero exit code.
  failed,

  /// The call has no final result, for example because it's still running,
  /// runs in the background, or was canceled.
  unfinished,
}

/// A tool call made by an agent.
final class const TrajectoryToolCall({
  /// The name of the tool.
  ///
  /// Calls to MCP tools made through `call_mcp_tool` are named
  /// `mcp_<server>_<tool>`, the way directly called MCP tools are.
  required final String tool,

  /// How the call ended.
  required final ToolOutcome outcome,

  /// The command line the call ran, if any.
  final String? command,

  /// The search query the call made, if any.
  final String? query,

  /// The file or directory the call acted on, if any.
  final String? path,

  /// The output of the call, without any header, if it [ToolOutcome.failed].
  final String? failureOutput,
}) {
  /// Whether this call may have modified the file at [path].
  ///
  /// This is true for calls to known file editing tools that didn't fail.
  bool get modifiesFile =>
      path != null &&
      outcome != ToolOutcome.failed &&
      _fileEditingTools.contains(tool);
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
/// nonzero exit code.
Trajectory summarizeTrajectory(ConversationTranscript transcript) {
  // Model call steps are keyed by identity, so these keys are unique.
  final answers = <(TranscriptStep, int), TranscriptStep>{
    for (final (:modelCall, :index, :answer) in pairToolCalls(transcript.steps))
      (modelCall, index): answer,
  };

  final turns = <TrajectoryTurn>[];
  var turn = _TurnBuilder();
  for (final step in transcript.steps) {
    if (step.type == StepType.userInput) {
      if (turn.isNotEmpty) turns.add(turn.build());
      turn = _TurnBuilder(
        request: step.userRequest,
        triggers: [..._triggers(step.content)],
      );
    }
    turn.recordTime(step.createdAt);
    if (step.type == StepType.plannerResponse) {
      turn.addModelCall(
        thinking: step.thinking,
        message: step.content,
        toolCalls: [
          for (final (index, call) in (step.toolCalls ?? const []).indexed)
            _summarizeToolCall(call, answers[(step, index)]),
        ],
      );
    }
  }
  if (turn.isNotEmpty) turns.add(turn.build());

  return Trajectory(conversationId: transcript.conversationId, turns: turns);
}

/// Collects the parts of a [TrajectoryTurn] while its steps are read.
final class _TurnBuilder({
  final String? request,
  final List<TurnTrigger> triggers = const [],
}) {
  final List<TrajectoryToolCall> _toolCalls = [];
  int _modelCalls = 0;
  DateTime? _start;
  DateTime? _end;
  String? _thinking;
  String? _reply;

  /// Whether the turn should be reported: it has a request or model calls.
  bool get isNotEmpty => request != null || _modelCalls > 0;

  /// Extends the turn's duration to include [time], if it's known.
  void recordTime(DateTime? time) {
    if (time == null) return;
    _start ??= time;
    _end = time;
  }

  /// Adds a model call with [thinking], [message], and [toolCalls].
  void addModelCall({
    required String thinking,
    required String message,
    required List<TrajectoryToolCall> toolCalls,
  }) {
    _modelCalls++;
    _thinking ??= _firstSentence(thinking);
    if (oneLine(message) case final reply when reply.isNotEmpty) {
      _reply = reply;
    }
    _toolCalls.addAll(toolCalls);
  }

  TrajectoryTurn build() => TrajectoryTurn(
    request: request,
    duration: _duration,
    triggers: triggers,
    thinking: _thinking,
    reply: _reply,
    toolCalls: _toolCalls,
  );

  /// The time from [_start] to [_end], or `null` if no time was recorded.
  ///
  /// Steps are in step order, but their times may not be.
  Duration? get _duration {
    if ((_start, _end) case (final start?, final end?)) {
      return end.isAfter(start) ? end.difference(start) : Duration.zero;
    }
    return null;
  }
}

/// Returns the items the user explicitly triggered in the user input
/// [content].
///
/// The runtime describes each one in the user input, as in
/// `/plan is a [Slash Command]:`.
Iterable<TurnTrigger> _triggers(String content) => _triggerPattern
    .allMatches(content)
    .map((match) => (kind: match[2]!, name: match[1]!));

final _triggerPattern = RegExp(r'([/\w-]+) is a \[([^\]]+)\]:');

/// Returns the first sentence of [text], on one line, or `null` if [text] is
/// blank.
String? _firstSentence(String text) {
  final line = oneLine(text);
  return line.isEmpty ? null : line.split(_sentenceBreakPattern).first;
}

final _sentenceBreakPattern = RegExp(r'(?<=[.!?])\s');

/// Summarizes the tool [call], answered by [answer] if it has been answered.
TrajectoryToolCall _summarizeToolCall(Object? call, TranscriptStep? answer) {
  final name = switch (call) {
    {'name': final String name} => name,
    _ => '(unknown)',
  };
  final arguments = _arguments(call);
  final command = _stringArgument(arguments, const ['CommandLine']);
  final outcome = _outcome(answer, ranCommand: command != null);
  return TrajectoryToolCall(
    tool: switch (arguments) {
      {'ServerName': final String server, 'ToolName': final String tool}
          when name == 'call_mcp_tool' =>
        'mcp_${server}_$tool',
      _ => name,
    },
    outcome: outcome,
    command: command,
    query: _stringArgument(arguments, const ['Query']),
    path: _stringArgument(arguments, _pathArguments),
    failureOutput: answer != null && outcome == ToolOutcome.failed
        ? _output(answer)
        : null,
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

/// The names of the arguments that tools take for the file or directory they
/// act on, in order of preference.
const _pathArguments = [
  'Path',
  'AbsolutePath',
  'TargetFile',
  'SearchPath',
  'DirectoryPath',
];

/// The tools that write or edit files, which are named by a path argument.
const _fileEditingTools = {
  'edit_file',
  'multi_replace_file_content',
  'replace_file_content',
  'write_file',
  'write_to_file',
};

/// Returns how a tool call answered by [answer] ended.
///
/// If the call [ranCommand], [answer]'s content is also checked for the
/// command's exit code.
ToolOutcome _outcome(TranscriptStep? answer, {required bool ranCommand}) {
  if (answer == null) return ToolOutcome.unfinished;
  if (answer.type == StepType.errorMessage ||
      answer.status == StepStatus.error ||
      answer.error != null ||
      answer.content.startsWith('Error:')) {
    return ToolOutcome.failed;
  }
  final exitCode =
      answer.exitCode ??
      (ranCommand ? _reportedExitCode(answer.content) : null);
  if (exitCode != null) {
    return exitCode == 0 ? ToolOutcome.succeeded : ToolOutcome.failed;
  }
  // Results that don't record a status are taken to be complete.
  return answer.status == StepStatus.done || answer.status.name.isEmpty
      ? ToolOutcome.succeeded
      : ToolOutcome.unfinished;
}

/// Returns the exit code reported in the [content] of a command's result, if
/// any.
int? _reportedExitCode(String content) =>
    int.tryParse(_exitCodePattern.firstMatch(content)?[1] ?? '');

/// Matches the line reporting a command's exit code in a command's result.
final _exitCodePattern = RegExp(
  r'^(?:The c|C)ommand exited with code (-?\d+)',
  multiLine: true,
);

/// Returns the output of the tool call answered by [answer], without the
/// header that precedes command output.
String _output(TranscriptStep answer) {
  final text = answer.error ?? answer.content;
  final outputStart = _outputHeaderPattern.firstMatch(text)?.end ?? 0;
  return text.substring(outputStart).trim();
}

/// Matches the end of the header of a command's result.
final _outputHeaderPattern = RegExp(
  r'^(?:Command )?[Oo]utput:',
  multiLine: true,
);
