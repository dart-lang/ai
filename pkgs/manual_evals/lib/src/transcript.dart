// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'text.dart';

/// The type of a [TranscriptStep].
///
/// [name] is the type as written in transcripts. The runtime adds types over
/// time, so any string is a valid type. The constants name the ones this
/// package uses; others include typed tool steps such as `RUN_COMMAND`.
extension type const StepType(String name) {
  /// A message from the user.
  static const userInput = StepType('USER_INPUT');

  /// A model call, which may call tools.
  static const plannerResponse = StepType('PLANNER_RESPONSE');

  /// The result of a tool call, for tools without a typed step.
  static const generic = StepType('GENERIC');

  /// A message from the runtime, such as a background task's result.
  static const systemMessage = StepType('SYSTEM_MESSAGE');

  /// A transient message.
  static const ephemeralMessage = StepType('EPHEMERAL_MESSAGE');

  /// An error, such as a tool call that couldn't be run.
  static const errorMessage = StepType('ERROR_MESSAGE');

  /// A checkpoint of the conversation.
  static const checkpoint = StepType('CHECKPOINT');
}

/// The source of a [TranscriptStep].
///
/// [name] is the source as written in transcripts. Any string is a valid
/// source; the constants name the known ones.
extension type const StepSource(String name) {
  /// A step the user took, such as sending a message.
  static const userExplicit = StepSource('USER_EXPLICIT');

  /// A step taken by the model, including the results of its tool calls.
  static const model = StepSource('MODEL');

  /// A step taken by the runtime.
  static const system = StepSource('SYSTEM');

  /// A step taken by the runtime's SDK.
  static const systemSdk = StepSource('SYSTEM_SDK');
}

/// The status of a [TranscriptStep].
///
/// [name] is the status as written in transcripts. Any string is a valid
/// status, including ones for steps that are still running or were canceled.
/// The constants name the ones this package uses.
extension type const StepStatus(String name) {
  /// The step completed successfully.
  static const done = StepStatus('DONE');

  /// The step failed.
  static const error = StepStatus('ERROR');

  /// The step was canceled.
  static const canceled = StepStatus('CANCELED');

  /// The step was interrupted before it finished.
  static const interrupted = StepStatus('INTERRUPTED');

  /// The status of a step that doesn't record one.
  static const unrecorded = StepStatus('');
}

/// A single step from a conversation transcript.
///
/// Steps use the Antigravity transcript schema; a [TranscriptSource] for
/// another agent must map its records onto it.
///
/// [json] is the decoded record, for reading fields without a getter. Getters
/// return a default value or `null` for fields that are missing or of an
/// unexpected type.
extension type TranscriptStep(Map<String, Object?> json) {
  /// The step's index in the original trajectory (`step_index`), if recorded.
  int? get stepIndex => _int('step_index');

  /// The step type (`type`), or an empty type if not recorded.
  StepType get type => StepType(_string('type') ?? '');

  /// The step source (`source`), or an empty source if not recorded.
  StepSource get source => StepSource(_string('source') ?? '');

  /// The step status (`status`), or an empty status if not recorded.
  StepStatus get status => StepStatus(_string('status') ?? '');

  /// When the step was created (`created_at`), if recorded.
  DateTime? get createdAt => DateTime.tryParse(_string('created_at') ?? '');

  /// The exit code of a command step (`exit_code`), if any.
  int? get exitCode => _int('exit_code');

  /// The error message of a failed step (`error`), if any.
  String? get error => _string('error');

  /// The error code of a failed step (`error_code`) as a string, if any.
  String? get errorCode => switch (json['error_code']) {
    final String code => code,
    final num code => '$code',
    _ => null,
  };

  /// The number of input tokens for this model call that were not read from
  /// the cache (`input_tokens`), if recorded.
  ///
  /// This excludes [cacheReadTokens], and any tokens written to the cache,
  /// which aren't recorded. Only [StepType.plannerResponse] steps record token
  /// usage.
  int? get inputTokens => _int('input_tokens');

  /// The number of input tokens for this model call that were read from the
  /// cache (`cache_read_tokens`), if recorded.
  int? get cacheReadTokens => _int('cache_read_tokens');

  /// The number of output tokens, including reasoning, for this model call
  /// (`output_tokens`), if recorded.
  int? get outputTokens => _int('output_tokens');

  /// Whether this step records any token usage: [inputTokens],
  /// [cacheReadTokens], or [outputTokens].
  bool get recordsTokenUsage =>
      inputTokens != null || cacheReadTokens != null || outputTokens != null;

  /// The text content of the step (`content`).
  String get content => _string('content') ?? '';

  /// The text of a [StepType.userInput] step's request, on one line.
  ///
  /// Agents built on the Antigravity runtime wrap the request in
  /// `<USER_REQUEST>` tags and add `<ADDITIONAL_METADATA>`. This is the text
  /// inside the tags if there is any, and otherwise the whole [content]
  /// without the metadata and tags.
  String get userRequest {
    final request = oneLine(
      _userRequestPattern.firstMatch(content)?.group(1) ?? '',
    );
    if (request.isNotEmpty) return request;
    return oneLine(
      content.replaceAll(_metadataPattern, ' ').replaceAll(_tagPattern, ' '),
    );
  }

  /// The slash commands, skills, and other items that a [StepType.userInput]
  /// step says the user explicitly triggered, in order.
  ///
  /// Agents built on the Antigravity runtime describe each one outside the
  /// `<USER_REQUEST>` tags, as in `/plan is a [Slash Command]:`.
  List<ExplicitTrigger> get triggers => [
    for (final match in _triggerPattern.allMatches(
      content.replaceAll(_userRequestPattern, ' '),
    ))
      (kind: match[2]!, name: match[1]!),
  ];

  /// The model's reasoning for the step (`thinking`), if any.
  String get thinking => _string('thinking') ?? '';

  /// The raw tool calls made in the step (`tool_calls`), if recorded.
  ///
  /// Each call is normally a map with a `name` and `args`.
  List<Object?>? get toolCalls => switch (json['tool_calls']) {
    final List<Object?> calls => calls,
    _ => null,
  };

  /// The names of the tools called in this step, in call order, with `null`
  /// for malformed calls.
  List<String?> get toolCallNames => [
    for (final call in toolCalls ?? const <Object?>[]) _toolCallName(call),
  ];

  /// The names of the fields truncated in this step (`truncated_fields`).
  ///
  /// Only abbreviated transcripts truncate fields.
  List<String> get truncatedFields => switch (json['truncated_fields']) {
    final List<Object?> fields => [...fields.whereType<String>()],
    _ => const [],
  };

  /// Whether this step is the result of a tool call.
  ///
  /// Results are [StepType.generic] or typed tool steps, such as
  /// `RUN_COMMAND`, from [StepSource.model]. They don't name their tool; use
  /// [pairToolCalls] to match them to their calls.
  bool get isToolResult =>
      source == StepSource.model && !_nonToolResultTypes.contains(type);

  String? _string(String key) => switch (json[key]) {
    final String value => value,
    _ => null,
  };

  int? _int(String key) => switch (json[key]) {
    final num value => value.toInt(),
    _ => null,
  };
}

/// Matches the text of a user request, which agents built on the Antigravity
/// runtime wrap in `<USER_REQUEST>` tags.
final _userRequestPattern = RegExp(
  r'<USER_REQUEST>(.*?)</USER_REQUEST>',
  dotAll: true,
);

/// Matches the metadata that agents built on the Antigravity runtime add to a
/// user request.
final _metadataPattern = RegExp(
  r'<ADDITIONAL_METADATA>.*?</ADDITIONAL_METADATA>',
  dotAll: true,
);

/// Matches an XML-style tag, such as `<USER_REQUEST>` or `</USER_REQUEST>`.
final _tagPattern = RegExp(r'</?[A-Z_]+>');

/// Matches the description of an explicitly triggered item in a user input,
/// as in `/plan is a [Slash Command]:`.
final _triggerPattern = RegExp(r'([/\w-]+) is a \[([^\]\n]+)\]:');

/// A slash command, skill, or other item that a user explicitly triggered,
/// such as `(kind: 'Slash Command', name: '/plan')`.
typedef ExplicitTrigger = ({String kind, String name});

/// Returns the name of the tool [call], or `null` if the call is malformed.
String? _toolCallName(Object? call) => switch (call) {
  {'name': final String name} => name,
  _ => null,
};

/// The name to report for a malformed tool call, which has no name.
const unknownToolName = '(unknown)';

/// Types of [StepSource.model] steps that are not tool results.
const _nonToolResultTypes = {
  StepType.plannerResponse,
  StepType.systemMessage,
  StepType.ephemeralMessage,
  StepType.errorMessage,
  StepType.checkpoint,
  StepType.userInput,
};

/// A tool result step and the name of the tool it is the result of.
typedef ToolResult = ({String? toolName, TranscriptStep step});

/// Matches each tool result in [steps] to its tool call.
///
/// This is [pairToolCalls] without the calls that are unanswered or couldn't
/// be run.
Iterable<ToolResult> pairToolResults(Iterable<TranscriptStep> steps) sync* {
  for (final pair in pairToolCalls(steps)) {
    if (pair.answer case final answer? when answer.isToolResult) {
      yield (toolName: pair.toolName, step: answer);
    }
  }
}

/// A tool call, the model call that made it, and the step that answered it.
///
/// The `call` is one of the `modelCall` step's [TranscriptStep.toolCalls],
/// normally a map with a `name` and `args`, and `toolName` is its name, or
/// `null` if it's malformed. The `answer` is the call's tool result (see
/// [TranscriptStep.isToolResult]), a [StepType.errorMessage] step if the call
/// couldn't be run, or `null` if the call wasn't answered.
typedef PairedToolCall = ({
  TranscriptStep modelCall,
  Object? call,
  String? toolName,
  TranscriptStep? answer,
});

/// Matches each tool call in [steps] to the step that answered it, if any.
///
/// Returns every call, in call order.
///
/// A [StepType.plannerResponse] step that calls N tools is followed by N
/// answers, in call order, possibly interleaved with other steps such as
/// system messages. An answer is a tool result, or a [StepType.errorMessage]
/// step for a call that couldn't be run. Calls that are still unanswered at
/// the next planner response or the end of [steps], such as calls that are
/// still running, have no answer. Extra results are ignored.
///
/// Any [StepType.errorMessage] step answers the next unanswered call, so an
/// error that isn't about a call, while calls are unanswered, shifts the
/// answers of the calls after it.
///
/// [steps] must be in step order, as [ConversationTranscript.steps] are.
Iterable<PairedToolCall> pairToolCalls(Iterable<TranscriptStep> steps) sync* {
  TranscriptStep? modelCall;
  var calls = const <Object?>[];
  var next = 0;

  PairedToolCall pair(int index, TranscriptStep? answer) => (
    modelCall: modelCall!,
    call: calls[index],
    toolName: _toolCallName(calls[index]),
    answer: answer,
  );

  for (final step in steps) {
    if (step.type == StepType.plannerResponse) {
      for (; next < calls.length; next++) {
        yield pair(next, null);
      }
      modelCall = step;
      calls = step.toolCalls ?? const [];
      next = 0;
    } else if (next < calls.length &&
        (step.isToolResult || step.type == StepType.errorMessage)) {
      yield pair(next++, step);
    }
  }
  for (; next < calls.length; next++) {
    yield pair(next, null);
  }
}

/// The steps of one turn of a conversation: a user request and what the
/// agent did in response.
///
/// The `steps` start with the `userInput` step, if there is one.
typedef TranscriptTurn = ({
  TranscriptStep? userInput,
  List<TranscriptStep> steps,
});

/// Splits [steps] into turns.
///
/// A turn starts at each [StepType.userInput] step. The steps before the first
/// one form a turn without a user input, which is left out if it has no
/// [StepType.plannerResponse] steps.
List<TranscriptTurn> splitTurns(Iterable<TranscriptStep> steps) {
  final turns = <TranscriptTurn>[(userInput: null, steps: [])];
  for (final step in steps) {
    if (step.type == StepType.userInput) {
      turns.add((userInput: step, steps: [step]));
    } else {
      turns.last.steps.add(step);
    }
  }
  if (!turns.first.steps.any((step) => step.type == StepType.plannerResponse)) {
    turns.removeAt(0);
  }
  return turns;
}

/// A loaded conversation transcript and its decoded steps.
final class ConversationTranscript {
  /// The ID of the conversation.
  final String conversationId;

  /// The path of the transcript file that was loaded.
  final String path;

  /// The decoded steps, in step order, without duplicates.
  final List<TranscriptStep> steps;

  /// The IDs of subagent conversations started by this conversation, in the
  /// order they were first reported, without duplicates.
  final List<String> subagentIds;

  /// Signs that the transcript wasn't fully understood, for example because
  /// its format has changed.
  final List<TranscriptWarning> warnings;

  /// Creates a transcript, copying [steps], [subagentIds], and [warnings]
  /// into unmodifiable lists.
  ConversationTranscript({
    required this.conversationId,
    required this.path,
    required List<TranscriptStep> steps,
    required List<String> subagentIds,
    List<TranscriptWarning> warnings = const [],
  }) : steps = List.unmodifiable(steps),
       subagentIds = List.unmodifiable(subagentIds),
       warnings = List.unmodifiable(warnings);
}

/// A conversation and all the subagent conversations it started,
/// transitively.
final class ConversationTree {
  /// The transcripts, in breadth-first order, starting with the [root].
  ///
  /// Each transcript's [ConversationTranscript.subagentIds] gives the tree's
  /// structure.
  final List<ConversationTranscript> transcripts;

  /// Every transcript's [ConversationTranscript.warnings], followed by
  /// problems loading subagents, such as missing transcripts.
  final List<TranscriptWarning> warnings;

  /// Creates a tree from [transcripts], which must start with the root and
  /// can't be empty, copying [transcripts] and [warnings] into unmodifiable
  /// lists.
  ConversationTree({
    required List<ConversationTranscript> transcripts,
    List<TranscriptWarning> warnings = const [],
  }) : assert(transcripts.isNotEmpty),
       transcripts = List.unmodifiable(transcripts),
       warnings = List.unmodifiable(warnings);

  /// The root conversation's transcript.
  ConversationTranscript get root => transcripts.first;
}

/// A sign that a transcript wasn't fully understood.
final class TranscriptWarning {
  /// The ID of the conversation with the problem.
  final String conversationId;

  /// The index of the step with the problem, if any.
  final int? stepIndex;

  /// A description of the problem.
  final String message;

  /// Creates a warning about [conversationId], optionally at [stepIndex].
  const TranscriptWarning(this.conversationId, this.message, {this.stepIndex});

  @override
  String toString() =>
      '$conversationId${stepIndex == null ? '' : ' (step $stepIndex)'}: '
      '$message';
}

/// Where an agent stores its conversation transcripts.
///
/// Extend this to support a new agent.
abstract base class TranscriptSource {
  /// Creates a transcript source.
  const TranscriptSource();

  /// A human-readable name for this source, used in messages.
  String get name;

  /// Descriptions of the locations this source searches, used in messages.
  List<String> get searchLocations => const [];

  /// The ID of the conversation running the current process, or `null` if
  /// this source can't detect one.
  String? get currentConversationId => null;

  /// Loads the transcript for [conversationId], or returns `null` if this
  /// source doesn't have it.
  ///
  /// May throw a `FileSystemException` if the transcript can't be read.
  Future<ConversationTranscript?> loadTranscript(String conversationId);
}

/// Thrown when a required transcript can't be found.
final class TranscriptNotFoundException implements Exception {
  /// The ID of the conversation whose transcript is missing.
  final String conversationId;

  /// The sources that were searched.
  final List<TranscriptSource> sources;

  /// Creates an exception for [conversationId], which wasn't found in
  /// [sources].
  TranscriptNotFoundException(this.conversationId, this.sources);

  @override
  String toString() {
    final buffer = StringBuffer(
      'Transcript not found for conversation $conversationId. Searched:',
    );
    if (sources.isEmpty) buffer.write(' (no transcript sources)');
    for (final source in sources) {
      final locations = source.searchLocations;
      buffer.write(
        '\n  ${source.name}: '
        '${locations.isEmpty ? '(nothing found)' : locations.join(', ')}',
      );
    }
    return buffer.toString();
  }
}
