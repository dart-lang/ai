// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'token_usage.dart';
import 'transcript.dart';

/// Returns a Markdown report of the token usage of the conversations in
/// [tree].
///
/// The report has a summary table with a row per conversation, followed by a
/// section per conversation with its turns and the tools it called (largest
/// results first), and any [ConversationTree.warnings].
String formatTokenReport(ConversationTree tree) {
  final usages = [
    for (final transcript in tree.transcripts) measureTokenUsage(transcript),
  ];
  final rootId = tree.root.conversationId;
  final allTokens = usages.fold(
    TokenCounts.zero,
    (sum, usage) => sum + usage.tokens,
  );
  final buffer = StringBuffer()
    ..writeln('# Token usage')
    ..writeln()
    ..writeln(
      'Counts are as recorded by the agent runtime. Input excludes cached '
      "input; tokens written to the cache aren't recorded.",
    )
    ..writeln()
    ..write(
      _table(
        [
          'Conversation',
          'Model calls',
          'Input',
          'Cached input',
          'Output',
          'Total',
          'Share',
        ],
        [
          for (final usage in usages)
            [
              _conversationName(usage.conversationId, rootId),
              _number(usage.modelCalls),
              ..._tokenCells(usage.tokens),
              _share(usage.tokens.total, allTokens.total),
            ],
          if (usages.length > 1)
            [
              '**Total**',
              _number(usages.fold(0, (sum, u) => sum + u.modelCalls)),
              ..._tokenCells(allTokens),
              _share(allTokens.total, allTokens.total),
            ],
        ],
      ),
    );

  for (final usage in usages) {
    buffer
      ..writeln()
      ..writeln('## ${_conversationName(usage.conversationId, rootId)}')
      ..writeln()
      ..write(
        _table(
          [
            'Turn',
            'Request',
            'Model calls',
            'Input',
            'Cached input',
            'Output',
            'Total',
          ],
          [
            for (final (index, turn) in usage.turns.indexed)
              [
                '${index + 1}',
                switch (turn.request) {
                  final request? => _shorten(request),
                  null => '(before the first request)',
                },
                _number(turn.modelCalls),
                ..._tokenCells(turn.tokens),
              ],
          ],
          textColumns: 2,
        ),
      );
    if (usage.tools.isNotEmpty) {
      buffer
        ..writeln()
        ..write(
          _table(
            ['Tool', 'Calls', 'Result characters'],
            [
              for (final MapEntry(key: name, value: tool) in _bySize(
                usage.tools,
              ))
                [name, _number(tool.calls), _number(tool.resultCharacters)],
            ],
          ),
        );
    }
    if (usage.unrecordedModelCalls > 0) {
      buffer
        ..writeln()
        ..writeln(
          usage.unrecordedModelCalls == 1
              ? "1 model call didn't record token usage, so its tokens aren't "
                    'counted.'
              : "${_number(usage.unrecordedModelCalls)} model calls didn't "
                    "record token usage, so their tokens aren't counted.",
        );
    }
  }

  if (tree.warnings.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('## Warnings')
      ..writeln()
      ..writeln(
        "Some transcripts weren't fully understood, so some usage may be "
        'missing.',
      )
      ..writeln();
    for (final warning in tree.warnings) {
      buffer.writeln('- $warning');
    }
  }
  return buffer.toString();
}

String _conversationName(String conversationId, String rootId) =>
    '`$conversationId`${conversationId == rootId ? ' (root)' : ''}';

List<String> _tokenCells(TokenCounts tokens) => [
  _number(tokens.input),
  _number(tokens.cacheRead),
  _number(tokens.output),
  _number(tokens.total),
];

/// Returns [text], cut to at most [_maxRequestLength] characters.
String _shorten(String text) {
  final runes = text.runes;
  return runes.length <= _maxRequestLength
      ? text
      : '${String.fromCharCodes(runes.take(_maxRequestLength - 1))}…';
}

/// The maximum length of a request shown in the report.
const _maxRequestLength = 60;

/// Returns the entries of [tools], largest results first, then by name.
List<MapEntry<String, ToolUsage>> _bySize(Map<String, ToolUsage> tools) =>
    tools.entries.toList()..sort((a, b) {
      final bySize = b.value.resultCharacters.compareTo(
        a.value.resultCharacters,
      );
      return bySize != 0 ? bySize : a.key.compareTo(b.key);
    });

/// Formats [part] as a percentage of [whole], for example `12.3%`.
String _share(int part, int whole) =>
    whole == 0 ? '–' : '${(part / whole * 100).toStringAsFixed(1)}%';

/// Formats [number] with comma thousands separators, for example `1,234,567`.
String _number(int number) {
  final digits = number.abs().toString();
  final buffer = StringBuffer(number < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// Returns a Markdown table with [headers] and [rows], with the first
/// [textColumns] columns aligned left and the rest, which hold numbers,
/// aligned right.
String _table(
  List<String> headers,
  List<List<String>> rows, {
  int textColumns = 1,
}) {
  String row(List<String> cells) => '| ${cells.map(_escape).join(' | ')} |\n';
  final alignments = [
    for (var i = 0; i < headers.length; i++) i < textColumns ? ':--' : '--:',
  ];
  return [row(headers), row(alignments), ...rows.map(row)].join();
}

/// Escapes [text] for use in a Markdown table cell.
String _escape(String text) =>
    text.replaceAll(r'\', r'\\').replaceAll('|', r'\|');
