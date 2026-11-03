// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:manual_evals/manual_evals.dart';
import 'package:test/test.dart';

import 'steps.dart';

void main() {
  test('reports usage per conversation, turn, and tool', () {
    final tree = ConversationTree(
      transcripts: [
        transcript(conversationId: 'root', [
          userInput(r'Fix the | bug in a\b'),
          modelCall(
            input: 1000,
            cacheRead: 20000,
            output: 300,
            tools: ['read_file', 'invoke_subagent'],
          ),
          toolResult('short'),
          toolResult('Created the following subagent: ...'),
          modelCall(input: 500, cacheRead: 0, output: 50),
          modelCall(),
          userInput('${'long ' * 20}request'),
        ]),
        transcript(conversationId: 'sub', [
          systemMessage('Prompt'),
          modelCall(input: 2000, cacheRead: 6000, output: 150),
        ]),
      ],
      warnings: [const TranscriptWarning('root', 'Something odd.')],
    );

    expect(formatTokenReport(tree), r'''
# Token usage

Counts are as recorded by the agent runtime. Input excludes cached input; tokens written to the cache aren't recorded.

| Conversation | Model calls | Input | Cached input | Output | Total | Share |
| :-- | --: | --: | --: | --: | --: | --: |
| `root` (root) | 3 | 1,500 | 20,000 | 350 | 21,850 | 72.8% |
| `sub` | 1 | 2,000 | 6,000 | 150 | 8,150 | 27.2% |
| **Total** | 4 | 3,500 | 26,000 | 500 | 30,000 | 100.0% |

## `root` (root)

| Turn | Request | Model calls | Input | Cached input | Output | Total |
| :-- | :-- | --: | --: | --: | --: | --: |
| 1 | Fix the \| bug in a\\b | 3 | 1,500 | 20,000 | 350 | 21,850 |
| 2 | long long long long long long long long long long long long… | 0 | 0 | 0 | 0 | 0 |

| Tool | Calls | Result characters |
| :-- | --: | --: |
| invoke_subagent | 1 | 35 |
| read_file | 1 | 5 |

1 model call didn't record token usage, so its tokens aren't counted.

## `sub`

| Turn | Request | Model calls | Input | Cached input | Output | Total |
| :-- | :-- | --: | --: | --: | --: | --: |
| 1 | (before the first request) | 1 | 2,000 | 6,000 | 150 | 8,150 |

## Warnings

Some transcripts weren't fully understood, so some usage may be missing.

- root: Something odd.
''');
  });

  test('omits the total row for a single conversation', () {
    final report = formatTokenReport(
      ConversationTree(transcripts: [transcript(conversationId: 'root', [])]),
    );

    expect(report, contains('| `root` (root) | 0 | 0 | 0 | 0 | 0 | – |'));
    expect(report, isNot(contains('**Total**')));
    expect(report, isNot(contains('## Warnings')));
  });
}
