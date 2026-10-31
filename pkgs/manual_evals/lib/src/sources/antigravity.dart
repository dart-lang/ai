// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../transcript.dart';

/// Transcripts written by Antigravity and other agents built on its runtime.
///
/// A conversation's transcript is
/// `<root>/<conversation-id>/.system_generated/logs/transcript_full.jsonl`,
/// where `<root>` is a `brain` directory. The abbreviated `transcript.jsonl`
/// beside it, which truncates long fields and JSON-encodes tool call
/// arguments, is only used if no full transcript is found.
final class AntigravityTranscriptSource extends TranscriptSource {
  /// The environment variable the runtime sets to the ID of the active
  /// conversation.
  static const conversationIdEnvironmentVariable =
      'ANTIGRAVITY_CONVERSATION_ID';

  /// The environment variable the runtime sets to its app data directory,
  /// which contains a `brain` directory.
  static const appDataDirEnvironmentVariable = 'ANTIGRAVITY_APP_DATA_DIR';

  /// The environment variable that overrides the `brain` directories this
  /// source searches.
  ///
  /// The value is a list of directories separated by `:` (`;` on Windows).
  static const rootsEnvironmentVariable = 'MANUAL_EVALS_ANTIGRAVITY_ROOTS';

  final Map<String, String> _environment;
  final List<String>? _roots;

  /// Creates a source that searches the `brain` directories [roots].
  ///
  /// If [roots] is omitted, they are found using [environment] (which
  /// defaults to [Platform.environment]):
  ///
  /// - If [rootsEnvironmentVariable] is set, its entries.
  /// - Otherwise, `brain` in the [appDataDirEnvironmentVariable] directory,
  ///   which may be outside the home directory, followed by every
  ///   `~/.gemini/<app>/brain` directory, sorted. Together, these cover the
  ///   active agent and every installed Antigravity-based agent.
  AntigravityTranscriptSource({
    List<String>? roots,
    Map<String, String>? environment,
  }) : _roots = roots,
       _environment = environment ?? Platform.environment;

  @override
  String get name => 'Antigravity';

  /// The `brain` directories this source searches, in order.
  ///
  /// If they are found using the environment, the home directory is scanned
  /// when this is first used.
  @override
  late final List<String> searchLocations = List.unmodifiable(
    _roots ?? _findRoots(_environment),
  );

  @override
  String? get currentConversationId {
    final id = _environment[conversationIdEnvironmentVariable]?.trim();
    return id == null || id.isEmpty ? null : id;
  }

  /// Loads the transcript for [conversationId].
  ///
  /// Returns `null` if there is no transcript or if [conversationId] contains
  /// characters other than letters, digits, `_`, and `-`.
  ///
  /// Lines that aren't JSON objects and invalid UTF-8 are skipped. Lines
  /// aren't always in step order, and a step is written again when its status
  /// changes, so steps are sorted by [TranscriptStep.stepIndex], keeping the
  /// last copy of each.
  ///
  /// Subagents are the conversation IDs reported by the results of
  /// `invoke_subagent` and `run_workflow` calls, matched to their calls with
  /// [pairToolResults]. A call that runs in the background reports its result
  /// in a later [StepType.systemMessage] from its task. Conversation IDs
  /// anywhere else, such as in file contents, are ignored. A workflow that
  /// fails or is canceled doesn't report the agents it started, so they are
  /// missing.
  ///
  /// [ConversationTranscript.warnings] reports skipped lines (except a
  /// partially written last line), completed subagent results without
  /// subagents, truncated subagent results, and background subagent tasks
  /// that never reported a result.
  @override
  Future<ConversationTranscript?> loadTranscript(String conversationId) async {
    if (!_conversationIdPattern.hasMatch(conversationId)) return null;
    final path = _findTranscriptFile(conversationId);
    if (path == null) return null;

    final stepsByIndex = <int, TranscriptStep>{};
    final unindexedSteps = <TranscriptStep>[];
    var skippedLineCount = 0;
    var lastLineSkipped = false;
    final lines = File(path)
        .openRead()
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter());
    await for (final line in lines) {
      if (line.trim().isEmpty) continue;
      final step = _tryDecodeStep(line);
      lastLineSkipped = step == null;
      if (step == null) {
        skippedLineCount++;
      } else if (step.stepIndex case final index?) {
        stepsByIndex[index] = step;
      } else {
        unindexedSteps.add(step);
      }
    }

    final steps = [
      for (final index in stepsByIndex.keys.toList()..sort())
        stepsByIndex[index]!,
      ...unindexedSteps,
    ];
    final warnings = <TranscriptWarning>[];
    // A partially written last line is expected while a transcript is being
    // written, so it isn't reported.
    final skippedCount = skippedLineCount - (lastLineSkipped ? 1 : 0);
    if (skippedCount > 0) {
      warnings.add(
        TranscriptWarning(
          conversationId,
          steps.isEmpty
              ? 'No line is a transcript step.'
              : skippedCount == 1
              ? "Skipped 1 line that isn't a transcript step."
              : "Skipped $skippedCount lines that aren't transcript steps.",
        ),
      );
    }

    final subagents = _findSubagents(conversationId, steps);
    return ConversationTranscript(
      conversationId: conversationId,
      path: path,
      steps: steps,
      subagentIds: [
        for (final id in subagents.ids)
          if (id != conversationId) id,
      ],
      warnings: [...warnings, ...subagents.warnings],
    );
  }

  /// Returns the path of the transcript file for [conversationId], if any,
  /// preferring a full transcript in any root over an abbreviated one.
  String? _findTranscriptFile(String conversationId) {
    for (final fileName in _transcriptFileNames) {
      for (final root in searchLocations) {
        final path = p.join(_logsDir(root, conversationId), fileName);
        if (File(path).existsSync()) return path;
      }
    }
    return null;
  }
}

// The on-disk layout of transcripts.

/// The directory in the home directory that contains the app data directories
/// of installed Antigravity-based agents.
const _geminiDirName = '.gemini';

/// The directory in an app data directory that contains a directory per
/// conversation.
const _brainDirName = 'brain';

/// The transcript file names to look for, in order of preference.
const _transcriptFileNames = ['transcript_full.jsonl', 'transcript.jsonl'];

/// Returns the directory containing [conversationId]'s transcripts in the
/// `brain` directory [root].
String _logsDir(String root, String conversationId) =>
    p.join(root, conversationId, '.system_generated', 'logs');

/// Matches a valid conversation ID.
final _conversationIdPattern = RegExp(r'^[\w-]+$');

/// Finds the `brain` directories using [environment], as described in
/// [AntigravityTranscriptSource.new].
List<String> _findRoots(Map<String, String> environment) {
  String? nonBlank(String key) => switch (environment[key]?.trim()) {
    final String v when v.isNotEmpty => v,
    _ => null,
  };

  if (nonBlank(AntigravityTranscriptSource.rootsEnvironmentVariable)
      case final override?) {
    final separator = Platform.isWindows ? ';' : ':';
    return {
      for (final root in override.split(separator))
        if (root.trim().isNotEmpty) p.normalize(root.trim()),
    }.toList();
  }

  final roots = <String>{};
  if (nonBlank(AntigravityTranscriptSource.appDataDirEnvironmentVariable)
      case final appDataDir?) {
    roots.add(p.normalize(p.join(appDataDir, _brainDirName)));
  }

  if (nonBlank('HOME') ?? nonBlank('USERPROFILE') case final home?) {
    final List<FileSystemEntity> apps;
    try {
      apps = Directory(p.join(home, _geminiDirName)).listSync();
    } on FileSystemException {
      return roots.toList();
    }
    roots.addAll(
      [
        for (final app in apps)
          if (app is Directory &&
              Directory(p.join(app.path, _brainDirName)).existsSync())
            p.normalize(p.join(app.path, _brainDirName)),
      ]..sort(),
    );
  }

  return roots.toList();
}

/// Decodes [line] as a [TranscriptStep], or returns `null` if it isn't a JSON
/// object.
TranscriptStep? _tryDecodeStep(String line) {
  if (line.trim().isEmpty) return null;
  try {
    if (jsonDecode(line) case final Map<String, Object?> json) {
      return TranscriptStep(json);
    }
  } on FormatException {
    // Skip malformed lines.
  }
  return null;
}

/// Returns the subagent conversation IDs reported in [steps], in the order
/// reported and without duplicates, and warnings about unreadable results.
({Set<String> ids, List<TranscriptWarning> warnings}) _findSubagents(
  String conversationId,
  List<TranscriptStep> steps,
) {
  final ids = <String>{};
  final warnings = <TranscriptWarning>[];
  final toolNamesByResult =
      Map<TranscriptStep, String?>.identity()..addEntries([
        for (final (:toolName, :step) in pairToolResults(steps))
          MapEntry(step, toolName),
      ]);
  final backgroundTasks = <String, _BackgroundTask>{};

  void warnIfTruncated(TranscriptStep step, String toolName) {
    if (step.truncatedFields.contains('content')) {
      warnings.add(
        TranscriptWarning(
          conversationId,
          'This $toolName result is truncated, so subagents may be missing.',
          stepIndex: step.stepIndex,
        ),
      );
    }
  }

  for (final step in steps) {
    if (step.type == StepType.systemMessage && backgroundTasks.isNotEmpty) {
      for (final message in step.content.split(_messagePrefix).skip(1)) {
        final sender = _messageSenderPattern.firstMatch(message)?.group(1);
        if (backgroundTasks[sender] case final task?) {
          final found = task.tool.extract(message);
          task.messages.add(message);
          task.foundCount += found.length;
          task.endedEarly |= _taskEndedEarlyPattern.hasMatch(message);
          ids.addAll(found);
          warnIfTruncated(step, task.tool.name);
        }
      }
      continue;
    }

    final tool = _subagentTools[toolNamesByResult[step]];
    if (tool == null) continue;
    final found = tool.extract(step.content);
    if (found.isEmpty) {
      if (_backgroundTaskPattern.firstMatch(step.content)?.group(1)
          case final taskId?) {
        backgroundTasks[taskId] = _BackgroundTask(tool, step.stepIndex);
        continue;
      }
    }
    ids.addAll(found);
    warnIfTruncated(step, tool.name);
    if (found.isEmpty &&
        _shouldReportSubagents(step) &&
        tool.expectsSubagents(step.content)) {
      warnings.add(
        TranscriptWarning(
          conversationId,
          "Couldn't find the subagents in this ${tool.name} result.",
          stepIndex: step.stepIndex,
        ),
      );
    }
  }

  for (final MapEntry(key: taskId, value: task) in backgroundTasks.entries) {
    if (task.messages.isEmpty) {
      warnings.add(
        TranscriptWarning(
          conversationId,
          '${task.tool.name} in background task $taskId never reported a '
          'result. It may still be running.',
          stepIndex: task.stepIndex,
        ),
      );
    } else if (task.foundCount == 0 &&
        !task.endedEarly &&
        task.messages.any(task.tool.expectsSubagents)) {
      warnings.add(
        TranscriptWarning(
          conversationId,
          "Couldn't find the subagents in the result of ${task.tool.name} in "
          'background task $taskId.',
          stepIndex: task.stepIndex,
        ),
      );
    }
  }

  return (ids: ids, warnings: warnings);
}

/// Whether the result [step] of a subagent tool call should report subagents.
///
/// Failed and canceled calls don't. Calls that are still running don't report
/// them yet, but if their result has any output besides timestamps, it should
/// be a background task notice.
bool _shouldReportSubagents(TranscriptStep step) => switch (step.status) {
  StepStatus.done => true,
  StepStatus.error || StepStatus.canceled || StepStatus.interrupted => false,
  _ => step.content.replaceAll(_timestampLinePattern, '').trim().isNotEmpty,
};

/// A tool that starts subagent conversations.
final class _SubagentTool {
  /// The tool's name.
  final String name;

  /// Returns the subagent conversation IDs in a result of this tool.
  final Iterable<String> Function(String result) extract;

  /// Whether a successful result of this tool should report subagents.
  final bool Function(String result) expectsSubagents;

  const _SubagentTool(this.name, this.extract, this.expectsSubagents);
}

/// A subagent tool call running in a background task.
final class _BackgroundTask {
  final _SubagentTool tool;
  final int? stepIndex;
  final messages = <String>[];
  int foundCount = 0;

  /// Whether the task failed or was canceled, so its result may legitimately
  /// report no subagents.
  bool endedEarly = false;

  _BackgroundTask(this.tool, this.stepIndex);
}

/// The tools that start subagents, by name.
final _subagentTools = {
  for (final tool in [
    // Every successful call starts at least one subagent.
    _SubagentTool('invoke_subagent', _invokeSubagentIds, (_) => true),
    // A workflow may only call tools, but its result still has a summary
    // line.
    _SubagentTool(
      'run_workflow',
      _runWorkflowIds,
      (result) =>
          result.contains(_workflowAgentMarker) ||
          !_workflowSummaryPattern.hasMatch(result),
    ),
  ])
    tool.name: tool,
};

/// Returns the conversation IDs in an `invoke_subagent` result, which reports
/// one or more JSON objects after the [_invokeSubagentBanner].
Iterable<String> _invokeSubagentIds(String result) {
  final start = result.indexOf(_invokeSubagentBanner);
  if (start == -1) return const [];
  return [
    for (final match in _jsonConversationIdPattern.allMatches(result, start))
      match.group(1)!,
  ];
}

/// Returns the conversation IDs in a `run_workflow` result, which has a line
/// per agent.
Iterable<String> _runWorkflowIds(String result) => [
  for (final match in _workflowAgentPattern.allMatches(result)) match.group(1)!,
];

// The runtime's display text.
//
// Tool results report subagents in text written for the model, not in
// structured fields. These match that text, the part of the format most likely
// to change; `tool/check_transcript_format.dart` reports when they stop
// matching.

/// Matches a timestamp line at the start of a tool result, for example
/// `Created At: 2026-10-29T23:48:50Z`.
final _timestampLinePattern = RegExp(
  r'^(?:Created|Completed) At: .*$',
  multiLine: true,
);

/// The start of the banner in an `invoke_subagent` result, which reads
/// "Created the following subagent:" or "...subagents:".
const _invokeSubagentBanner = 'Created the following subagent';

/// The start of the tag on each agent line in a `run_workflow` result.
const _workflowAgentMarker = '[agent:';

/// The prefix of each of the messages in a [StepType.systemMessage] step.
const _messagePrefix = '[Message] ';

/// Matches a conversation ID in a JSON object, for example
/// `"conversationId": "abc-123"`.
final _jsonConversationIdPattern = RegExp(r'"conversationId":\s*"([\w-]+)"');

/// Matches a workflow agent line, of the form
/// `- [agent:<type>] <title>: <status>[, turn <n>] (<id>): <result>`.
final _workflowAgentPattern = RegExp(
  r'^[ \t]*(?:- )?'
  '${RegExp.escape(_workflowAgentMarker)}'
  r'[^\]\n]*\][^\n]*?: \w+(?:, turn \d+)? \(([\w-]+)\)(?::|[ \t]*$)',
  multiLine: true,
);

/// Matches the summary line of a `run_workflow` result, for example
/// `Workflow "Review files" completed.` or, without a description,
/// `Workflow completed.`
final _workflowSummaryPattern = RegExp(
  r'^Workflow(?: ".*")? \w+\.$',
  multiLine: true,
);

/// Matches the task ID in the result of a tool call that is running in the
/// background, which reports its final result in a later
/// [StepType.systemMessage].
final _backgroundTaskPattern = RegExp(
  r'^Tool is running as a background task with task id: (\S+)[ \t]*$',
  multiLine: true,
);

/// Matches the sender at the start of a message, after its [_messagePrefix].
final _messageSenderPattern = RegExp(r'^timestamp=\S+ sender=(\S+)');

/// Matches a background task message reporting that the task failed or was
/// canceled, for example `content=Task id "<id>" failed with result:`.
final _taskEndedEarlyPattern = RegExp(
  r'content=Task id "[^"\n]*" (?:failed|was canceled) with result:',
);
