// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:manual_evals/src/text.dart';
import 'package:test/test.dart';

void main() {
  test('oneLine collapses whitespace', () {
    expect(oneLine('  a\n\tb  c '), 'a b c');
  });

  test('shorten cuts long text with an ellipsis', () {
    expect(shorten('abc', 3), 'abc');
    expect(shorten('abcd', 3), 'ab…');
  });

  test('formatNumber adds thousands separators', () {
    expect(formatNumber(123), '123');
    expect(formatNumber(1234567), '1,234,567');
    expect(formatNumber(-1000), '-1,000');
  });

  test('formatPercent shows – for a zero whole', () {
    expect(formatPercent(1, 3), '33.3%');
    expect(formatPercent(1, 0), '–');
  });

  test('conversationName marks the root', () {
    expect(conversationName('a', 'a'), '`a` (root)');
    expect(conversationName('b', 'a'), '`b`');
  });

  test('markdownTable aligns numbers right and escapes cells', () {
    expect(
      markdownTable(
        ['Name', 'Count'],
        [
          ['a|b\nc', '1'],
        ],
      ),
      '| Name | Count |\n| :-- | --: |\n| a\\|b c | 1 |\n',
    );
  });

  test('codeSpan fences backticks in the text', () {
    expect(codeSpan('a'), '`a`');
    expect(codeSpan('a `b` c'), '``a `b` c``');
    expect(codeSpan('`a`'), '`` `a` ``');
    expect(codeSpan(' a '), '`  a  `');
    expect(codeSpan(' a'), '` a`');
  });

  test('codeBlock fences and indents the text', () {
    expect(codeBlock('a\n\nb', indent: '  '), '  ```\n  a\n\n  b\n  ```\n');
    expect(codeBlock('```'), '````\n```\n````\n');
  });
}
