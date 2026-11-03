// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'text.dart';
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
      markdownTable(
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
              formatNumber(usage.modelCalls),
              ..._tokenCells(usage.tokens),
              formatPercent(usage.tokens.total, allTokens.total),
            ],
          if (usages.length > 1)
            [
              '**Total**',
              formatNumber(usages.fold(0, (sum, u) => sum + u.modelCalls)),
              ..._tokenCells(allTokens),
              formatPercent(allTokens.total, allTokens.total),
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
        markdownTable(
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
                  final request? => shorten(request, _maxRequestLength),
                  null => '(before the first request)',
                },
                formatNumber(turn.modelCalls),
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
          markdownTable(
            ['Tool', 'Calls', 'Result characters'],
            [
              for (final MapEntry(key: name, value: tool) in _bySize(
                usage.tools,
              ))
                [
                  name,
                  formatNumber(tool.calls),
                  formatNumber(tool.resultCharacters),
                ],
            ],
          ),
        );
    }
    if (usage.unrecordedModelCalls case final unrecorded when unrecorded > 0) {
      buffer
        ..writeln()
        ..writeln(
          unrecorded == 1
              ? "1 model call didn't record token usage, so its tokens aren't "
                    'counted.'
              : "${formatNumber(unrecorded)} model calls didn't record token "
                    "usage, so their tokens aren't counted.",
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
  formatNumber(tokens.input),
  formatNumber(tokens.cacheRead),
  formatNumber(tokens.output),
  formatNumber(tokens.total),
];

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
