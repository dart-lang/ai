// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

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

  /// The text content of the step (`content`).
  String get content => _string('content') ?? '';

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
    for (final call in toolCalls ?? const <Object?>[])
      switch (call) {
        {'name': final String name} => name,
        _ => null,
      },
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
  /// [pairToolResults] to match them to their calls.
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
/// A [StepType.plannerResponse] step that calls N tools is followed by N tool
/// results (see [TranscriptStep.isToolResult]), in call order, possibly
/// interleaved with other steps such as system messages. A call that couldn't
/// be run is answered by a [StepType.errorMessage] step instead, which uses up
/// that call. Extra results are ignored.
///
/// [steps] must be in step order, as [ConversationTranscript.steps] are.
Iterable<ToolResult> pairToolResults(Iterable<TranscriptStep> steps) sync* {
  var toolNames = const <String?>[];
  var next = 0;
  for (final step in steps) {
    if (step.type == StepType.plannerResponse) {
      toolNames = step.toolCallNames;
      next = 0;
    } else if (next < toolNames.length) {
      if (step.isToolResult) {
        yield (toolName: toolNames[next++], step: step);
      } else if (step.type == StepType.errorMessage) {
        next++;
      }
    }
  }
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
