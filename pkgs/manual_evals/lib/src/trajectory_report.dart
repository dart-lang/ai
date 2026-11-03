// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

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
/// If [homeDirectory] is given, paths in it are shortened to start with `~`.
String formatTrajectoryReport(ConversationTree tree, {String? homeDirectory}) {
  final trajectories = [
    for (final transcript in tree.transcripts) summarizeTrajectory(transcript),
  ];
  final toolCalls = [
    for (final trajectory in trajectories) ...trajectory.toolCalls,
  ];
  final report = _TrajectoryReport(
    rootId: tree.root.conversationId,
    tidy: _homeShortener(homeDirectory),
  );
  for (final trajectory in trajectories) {
    report.writeTimeline(trajectory);
  }
  report
    ..writeToolCalls(toolCalls)
    ..writeModifiedFiles(toolCalls)
    ..writeWarnings(tree.warnings);
  return '$report';
}

/// Returns a function that replaces each path in [homeDirectory], or the
/// directory itself, with `~`, or that does nothing if there's no
/// [homeDirectory].
String Function(String text) _homeShortener(String? homeDirectory) {
  final home = homeDirectory?.replaceFirst(_trailingSeparatorsPattern, '');
  if (home == null || home.isEmpty) return (text) => text;
  // Windows paths may use either separator and are case-insensitive. The
  // report may be formatted on another platform, so tell from the path.
  final isWindows = home.contains(r'\') || _drivePattern.hasMatch(home);
  final homePattern = isWindows
      ? home.split(_separatorPattern).map(RegExp.escape).join(r'[/\\]')
      : RegExp.escape(home);
  // Only match the whole directory: not within a longer path, such as
  // `/var/home/me`, or a sibling, such as `/home/meg`.
  final pattern = RegExp(
    '(?<![\\w.~/\\\\-])$homePattern(?![\\w.-])',
    caseSensitive: !isWindows,
  );
  return (text) => text.replaceAll(pattern, '~');
}

final _trailingSeparatorsPattern = RegExp(r'[/\\]+$');

final _separatorPattern = RegExp(r'[/\\]');

/// Matches a Windows drive letter at the start of a path, such as `C:`.
final _drivePattern = RegExp('^[A-Za-z]:');

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
    _section('## ${conversationName(trajectory.conversationId, rootId)}');
    if (trajectory.turns.isEmpty) {
      _lines.add('No turns.');
      return;
    }
    var requestNumber = 0;
    for (final turn in trajectory.turns) {
      if (turn.request != null) requestNumber++;
      _writeTurn(turn, switch (turn.request) {
        final request? => 'Turn $requestNumber: ${_quote(request)}',
        null => 'Before the first request',
      });
    }
  }

  /// Writes [turn] under a heading with [title] and its duration.
  void _writeTurn(TrajectoryTurn turn, String title) {
    final duration = switch (turn.duration) {
      final duration? => ' (${_formatDuration(duration)})',
      null => '',
    };
    _section('### $title$duration');
    _lines.addAll([
      if (turn.initialMessage case final message?)
        '- Message: ${_quote(message)}',
      for (final (:kind, :name) in turn.triggers)
        '- Triggered ${codeSpan(name)} ($kind)',
      if (turn.thinking case final thinking?) '- Thinking: ${_quote(thinking)}',
    ]);
    for (final call in turn.toolCalls) {
      _writeToolCall(call);
    }
    if (turn.reply case final reply?) _lines.add('- Replied: ${_quote(reply)}');
  }

  /// Writes [call] with its outcome, what it acted on, and the end of its
  /// output if it failed.
  void _writeToolCall(TrajectoryToolCall call) {
    final marker = switch (call.outcome) {
      ToolCallOutcome.succeeded => '✅',
      ToolCallOutcome.failed => '❌',
      ToolCallOutcome.unfinished => '⏳',
    };
    final subject = switch (call) {
      TrajectoryToolCall(:final command?) => _quote(command),
      TrajectoryToolCall(:final query?, :final path?) =>
        '${_quote(query)} in ${_quote(p.basename(path))}',
      TrajectoryToolCall(:final query?) => _quote(query),
      TrajectoryToolCall(:final path?) => _quote(p.basename(path)),
      _ => null,
    };
    _lines.add(['-', marker, codeSpan(call.tool), ?subject].join(' '));
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
    final tools = byTool.entries.toList()
      ..sort((a, b) {
        final byCalls = b.value.length.compareTo(a.value.length);
        return byCalls != 0 ? byCalls : a.key.compareTo(b.key);
      });
    _lines.add(
      markdownTable(
        ['Tool', 'Calls', 'Failed', 'Success rate'],
        [
          for (final MapEntry(key: tool, value: calls) in tools)
            [tool, ..._outcomeCells(calls)],
          if (tools.length > 1) ['**Total**', ..._outcomeCells(toolCalls)],
        ],
      ).trimRight(),
    );
    final unfinished = toolCalls
        .where((call) => call.outcome == ToolCallOutcome.unfinished)
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
      if (call case TrajectoryToolCall(modifiesFile: true, :final path?)) {
        edits.update(tidy(path), (count) => count + 1, ifAbsent: () => 1);
      }
    }
    if (edits.isEmpty) return;
    _section('## Files modified');
    final files = edits.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final MapEntry(key: path, value: count) in files) {
      _lines.add(
        '- ${codeSpan(path)} (${count == 1 ? '1 edit' : '$count edits'})',
      );
    }
  }

  /// Writes [warnings] about transcripts that weren't fully understood.
  void writeWarnings(List<TranscriptWarning> warnings) {
    if (warnings.isEmpty) return;
    _section('## Warnings');
    _lines
      ..add(
        "Some transcripts weren't fully understood, so some steps may be "
        'missing.',
      )
      ..add('')
      ..addAll(warnings.map((warning) => '- $warning'));
  }

  /// Starts a section with [heading], with a blank line before and after it.
  void _section(String heading) {
    if (_lines.last.isNotEmpty) _lines.add('');
    _lines
      ..add(heading)
      ..add('');
  }

  /// Returns [text], from a transcript, on one line, shortened, and as a code
  /// span, or `(empty)` if it's blank.
  String _quote(String text) {
    final line = oneLine(tidy(text));
    return line.isEmpty ? '(empty)' : codeSpan(shorten(line, _maxQuoteLength));
  }

  @override
  String toString() => '${_lines.join('\n')}\n';
}

/// Returns the number of [calls], how many failed, and their success rate,
/// formatted as table cells.
List<String> _outcomeCells(List<TrajectoryToolCall> calls) {
  int count(ToolCallOutcome outcome) =>
      calls.where((call) => call.outcome == outcome).length;
  final succeeded = count(ToolCallOutcome.succeeded);
  final failed = count(ToolCallOutcome.failed);
  return [
    formatNumber(calls.length),
    formatNumber(failed),
    formatPercent(succeeded, succeeded + failed),
  ];
}

/// Returns the last [_maxOutputLines] non-blank lines of [output], which is
/// where errors are usually reported.
String _excerpt(String output) {
  final lines = [
    for (final line in LineSplitter.split(output))
      if (line.trim().isNotEmpty) line.trimRight(),
  ];
  return lines.length <= _maxOutputLines
      ? lines.join('\n')
      : ['…', ...lines.sublist(lines.length - _maxOutputLines)].join('\n');
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
