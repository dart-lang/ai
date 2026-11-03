// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;

import 'text.dart';
import 'trajectory.dart';
import 'transcript.dart';

/// Returns a Markdown report of what the agents in [tree] did.
///
/// The report has a timeline of each conversation's turns, followed by a table
/// of the tool calls in all the conversations, the files they modified, and
/// any [ConversationTree.warnings].
///
/// Paths in the [homeDirectory] (which defaults to the user's home directory)
/// are shortened to start with `~`.
String formatTrajectoryReport(ConversationTree tree, {String? homeDirectory}) {
  final home = homeDirectory ?? _homeDirectory;
  final trajectories = [
    for (final transcript in tree.transcripts) summarizeTrajectory(transcript),
  ];
  final report = _TrajectoryReport(
    rootId: tree.root.conversationId,
    tidy: home == null || home.isEmpty
        ? (text) => text
        : (text) => text.replaceAll(home, '~'),
  );
  for (final trajectory in trajectories) {
    report.writeTimeline(trajectory);
  }
  final toolCalls = [
    for (final trajectory in trajectories) ...trajectory.toolCalls,
  ];
  report
    ..writeToolCalls(toolCalls)
    ..writeModifiedFiles(toolCalls)
    ..writeWarnings(tree.warnings);
  return report.toString();
}

String? get _homeDirectory =>
    Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'];

/// The maximum length of a request, command, or other text quoted from a
/// transcript in the report.
const _maxQuoteLength = 80;

/// The maximum number of lines of a failed tool call's output in the report.
const _maxOutputLines = 5;

/// Writes the sections of a trajectory report.
final class _TrajectoryReport({
  /// The ID of the root conversation.
  required final String rootId,

  /// Shortens the paths in a text quoted from a transcript.
  required final String Function(String text) tidy,
}) {
  final List<String> _lines = ['# Trajectory'];

  /// Writes the turns of [trajectory], with each turn's tool calls and the
  /// details that explain them.
  void writeTimeline(Trajectory trajectory) {
    _section('## ${_conversationName(trajectory.conversationId)}');
    if (trajectory.turns.isEmpty) {
      _lines.add('No turns.');
      return;
    }
    var requestNumber = 0;
    for (final turn in trajectory.turns) {
      final title = switch (turn.request) {
        null => 'Before the first request',
        final request => 'Turn ${++requestNumber}: ${_quote(request)}',
      };
      final duration = switch (turn.duration) {
        final duration? => ' (${_formatDuration(duration)})',
        null => '',
      };
      _section('### $title$duration');
      for (final (:kind, :name) in turn.triggers) {
        _lines.add('- Triggered ${codeSpan(name)} ($kind)');
      }
      if (turn.thinking case final thinking?) {
        _lines.add('- Thinking: ${_quote(thinking)}');
      }
      for (final call in turn.toolCalls) {
        _writeToolCall(call);
      }
      if (turn.reply case final reply?) {
        _lines.add('- Replied: ${_quote(reply)}');
      }
    }
  }

  void _writeToolCall(TrajectoryToolCall call) {
    final marker = switch (call.outcome) {
      ToolOutcome.succeeded => '✅',
      ToolOutcome.failed => '❌',
      ToolOutcome.unfinished => '⏳',
    };
    final subject = switch (call) {
      TrajectoryToolCall(:final command?) => _quote(command),
      TrajectoryToolCall(:final query?, :final path?) =>
        '${_quote(query)} in ${p.basename(path)}',
      TrajectoryToolCall(:final query?) => _quote(query),
      TrajectoryToolCall(:final path?) => p.basename(path),
      _ => null,
    };
    _lines.add(
      '- $marker ${codeSpan(call.tool)}${subject == null ? '' : ' $subject'}',
    );
    if (call.failureOutput case final output? when output.isNotEmpty) {
      _lines.add(codeBlock(_excerpt(tidy(output)), indent: '  ').trimRight());
    }
  }

  /// Writes a table of the calls to each tool in [toolCalls], most called
  /// first.
  void writeToolCalls(List<TrajectoryToolCall> toolCalls) {
    _section('## Tool calls');
    if (toolCalls.isEmpty) {
      _lines.add('No tool calls.');
      return;
    }
    final byTool = <String, List<TrajectoryToolCall>>{};
    for (final call in toolCalls) {
      (byTool[call.tool] ??= []).add(call);
    }
    final tools = byTool.keys.toList()
      ..sort((a, b) {
        final byCalls = byTool[b]!.length.compareTo(byTool[a]!.length);
        return byCalls != 0 ? byCalls : a.compareTo(b);
      });
    _lines.add(
      markdownTable(
        ['Tool', 'Calls', 'Failed', 'Success rate'],
        [
          for (final tool in tools) [tool, ..._outcomeCells(byTool[tool]!)],
          if (tools.length > 1) ['**Total**', ..._outcomeCells(toolCalls)],
        ],
      ).trimRight(),
    );
    final unfinished = toolCalls
        .where((call) => call.outcome == ToolOutcome.unfinished)
        .length;
    if (unfinished > 0) {
      _lines
        ..add('')
        ..add(
          unfinished == 1
              ? "1 call hadn't finished, so it isn't counted in success rates."
              : "${formatNumber(unfinished)} calls hadn't finished, so they "
                    "aren't counted in success rates.",
        );
    }
  }

  /// Writes the files that [toolCalls] may have modified, with the number of
  /// calls that modified each one.
  void writeModifiedFiles(List<TrajectoryToolCall> toolCalls) {
    final edits = <String, int>{};
    for (final call in toolCalls) {
      if (call.modifiesFile) {
        final path = tidy(call.path!);
        edits[path] = (edits[path] ?? 0) + 1;
      }
    }
    if (edits.isEmpty) return;
    _section('## Files modified');
    for (final path in edits.keys.toList()..sort()) {
      final count = edits[path]!;
      _lines.add(
        '- ${codeSpan(path)} (${count == 1 ? '1 edit' : '$count edits'})',
      );
    }
  }

  void writeWarnings(List<TranscriptWarning> warnings) {
    if (warnings.isEmpty) return;
    _section('## Warnings');
    _lines
      ..add(
        "Some transcripts weren't fully understood, so some steps may be "
        'missing.',
      )
      ..add('')
      ..addAll([for (final warning in warnings) '- $warning']);
  }

  /// Starts a section with [heading], with a blank line before and after it.
  void _section(String heading) {
    if (_lines.last.isNotEmpty) _lines.add('');
    _lines
      ..add(heading)
      ..add('');
  }

  String _conversationName(String conversationId) => conversationId == rootId
      ? '${codeSpan(conversationId)} (root)'
      : codeSpan(conversationId);

  /// Returns [text], from a transcript, shortened and as a code span.
  String _quote(String text) => codeSpan(shorten(tidy(text), _maxQuoteLength));

  @override
  String toString() => '${_lines.join('\n')}\n';
}

/// Returns the number of [calls], how many failed, and their success rate,
/// formatted as table cells.
List<String> _outcomeCells(List<TrajectoryToolCall> calls) {
  int count(ToolOutcome outcome) =>
      calls.where((call) => call.outcome == outcome).length;
  final succeeded = count(ToolOutcome.succeeded);
  final failed = count(ToolOutcome.failed);
  return [
    formatNumber(calls.length),
    formatNumber(failed),
    formatPercent(succeeded, succeeded + failed),
  ];
}

/// Returns the first [_maxOutputLines] non-blank lines of [output].
String _excerpt(String output) {
  final lines = [
    for (final line in output.split('\n'))
      if (line.trim().isNotEmpty) line.trimRight(),
  ];
  return [
    ...lines.take(_maxOutputLines),
    if (lines.length > _maxOutputLines) '…',
  ].join('\n');
}

/// Formats [duration] to the second, for example `45s` or `1h 2m 3s`.
String _formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes % 60;
  final seconds = duration.inSeconds % 60;
  return [
    if (hours > 0) '${hours}h',
    if (hours > 0 || minutes > 0) '${minutes}m',
    '${seconds}s',
  ].join(' ');
}
