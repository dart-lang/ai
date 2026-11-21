// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Helpers for formatting text and Markdown in reports.
library;

import 'dart:math';

/// Returns [text] on one line, with each run of whitespace replaced by a
/// single space.
String oneLine(String text) => text.replaceAll(_whitespacePattern, ' ').trim();

final _whitespacePattern = RegExp(r'\s+');

/// Returns [text], cut to at most [maxLength] characters, ending in `…` if it
/// was cut.
///
/// Characters are counted as runes, so a cut may split a combining sequence.
String shorten(String text, int maxLength) {
  assert(maxLength > 0);
  final runes = text.runes;
  return runes.length <= maxLength
      ? text
      : '${String.fromCharCodes(runes.take(maxLength - 1))}…';
}

/// Formats [part] as a percentage of [whole], for example `12.3%`, or `–` if
/// [whole] is zero.
String formatPercent(int part, int whole) =>
    whole == 0 ? '–' : '${(part / whole * 100).toStringAsFixed(1)}%';

/// Formats [number] with comma thousands separators, for example `1,234,567`.
String formatNumber(int number) {
  final digits = number.abs().toString();
  final buffer = StringBuffer(number < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// Returns the name of the conversation [conversationId] for a report about
/// the conversation [rootId] and its subagents.
String conversationName(String conversationId, String rootId) =>
    '${codeSpan(conversationId)}${conversationId == rootId ? ' (root)' : ''}';

/// Returns a Markdown table with [headers] and [rows], with the first
/// [textColumns] columns aligned left and the rest, which hold numbers,
/// aligned right.
String markdownTable(
  List<String> headers,
  List<List<String>> rows, {
  int textColumns = 1,
}) {
  String row(List<String> cells) =>
      '| ${cells.map(_escapeCell).join(' | ')} |\n';
  final alignments = [
    for (var i = 0; i < headers.length; i++) i < textColumns ? ':--' : '--:',
  ];
  return [row(headers), row(alignments), ...rows.map(row)].join();
}

/// Escapes [text] for use in a Markdown table cell, which must be on one
/// line.
String _escapeCell(String text) =>
    oneLine(text).replaceAll(r'\', r'\\').replaceAll('|', r'\|');

/// Returns [text], which must not be empty, as a Markdown code span.
///
/// The span is fenced with more backticks than any run of backticks in
/// [text], so it can hold any text on one line.
String codeSpan(String text) {
  assert(text.isNotEmpty);
  final fence = '`' * (_longestBacktickRun(text) + 1);
  // Renderers strip one space from each end of a span that starts and ends
  // with a space, and a span can't start or end with a backtick, so pad those.
  final needsPadding =
      text.startsWith('`') ||
      text.endsWith('`') ||
      (text.startsWith(' ') && text.endsWith(' ') && text.trim().isNotEmpty);
  final padding = needsPadding ? ' ' : '';
  return '$fence$padding$text$padding$fence';
}

/// Returns [text] as a fenced Markdown code block, with each line, including
/// the fences but not blank lines, starting with [indent].
///
/// The fence is longer than any run of backticks in [text], so the block can
/// hold any text.
String codeBlock(String text, {String indent = ''}) {
  final fence = '`' * max(3, _longestBacktickRun(text) + 1);
  return [
    fence,
    ...text.split('\n'),
    fence,
  ].map((line) => line.isEmpty ? '\n' : '$indent$line\n').join();
}

int _longestBacktickRun(String text) => _backtickRunPattern
    .allMatches(text)
    .fold(0, (longest, match) => max(longest, match[0]!.length));

final _backtickRunPattern = RegExp('`+');
