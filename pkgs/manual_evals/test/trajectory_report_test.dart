// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:manual_evals/manual_evals.dart';
import 'package:test/test.dart';

import 'steps.dart';

void main() {
  test('reports each turn, the tool calls, and the files modified', () {
    final tree = ConversationTree(
      transcripts: [
        transcript(conversationId: 'root', [
          {...userInput('Fix the `bug`'), 'created_at': '2026-01-01T00:00:00Z'},
          modelCall(
            thinking: 'Look first. Then fix.',
            calls: [
              toolCall('run_command', {'CommandLine': 'cat /home/me/a.dart'}),
              toolCall('edit_file', {'Path': '/home/me/a.dart'}),
              toolCall('invoke_subagent'),
            ],
          ),
          toolResult('Command exited with code 0.\nCommand output:\ncode'),
          toolResult('Edited.'),
          toolResult('Started subagent sub.'),
          {
            ...modelCall(
              content: 'Fixed it.',
              calls: [
                toolCall('run_command', {'CommandLine': 'dart test'}),
              ],
            ),
            'created_at': '2026-01-01T01:02:03Z',
          },
          toolResult(
            'Command exited with code 1.\n'
            'Command output:\n'
            '${[for (var i = 1; i <= 7; i++) 'line $i'].join('\n')}',
          ),
        ]),
        transcript(conversationId: 'sub', [
          modelCall(
            calls: [
              toolCall('grep_search', {
                'Query': 'bug',
                'SearchPath': '/home/me/lib',
              }),
              toolCall('write_file', {'Path': '/home/me/a.dart'}),
            ],
          ),
          toolResult('matches'),
        ]),
      ],
      warnings: [const TranscriptWarning('root', 'Something odd.')],
    );

    expect(formatTrajectoryReport(tree, homeDirectory: '/home/me'), '''
# Trajectory

## `root` (root)

### Turn 1: `` Fix the `bug` `` (1h 2m 3s)

- Thinking: `Look first.`
- ✅ `run_command` `cat ~/a.dart`
- ✅ `edit_file` a.dart
- ✅ `invoke_subagent`
- ❌ `run_command` `dart test`
  ```
  line 1
  line 2
  line 3
  line 4
  line 5
  …
  ```
- Replied: `Fixed it.`

## `sub`

### Before the first request

- ✅ `grep_search` `bug` in lib
- ⏳ `write_file` a.dart

## Tool calls

| Tool | Calls | Failed | Success rate |
| :-- | --: | --: | --: |
| run_command | 2 | 1 | 50.0% |
| edit_file | 1 | 0 | 100.0% |
| grep_search | 1 | 0 | 100.0% |
| invoke_subagent | 1 | 0 | 100.0% |
| write_file | 1 | 0 | – |
| **Total** | 6 | 1 | 80.0% |

1 call hadn't finished, so it isn't counted in success rates.

## Files modified

- `~/a.dart` (2 edits)

## Warnings

Some transcripts weren't fully understood, so some steps may be missing.

- root: Something odd.
''');
  });

  test('says when there are no turns or tool calls', () {
    final tree = ConversationTree(
      transcripts: [transcript(conversationId: 'root', [])],
    );

    expect(formatTrajectoryReport(tree, homeDirectory: ''), '''
# Trajectory

## `root` (root)

No turns.

## Tool calls

No tool calls.
''');
  });

  test('shortens long quotes', () {
    final tree = ConversationTree(
      transcripts: [
        transcript([userInput('${'long ' * 20}request')]),
      ],
    );

    expect(
      formatTrajectoryReport(tree, homeDirectory: ''),
      contains('### Turn 1: `${'long ' * 15}long…`\n'),
    );
  });
}
