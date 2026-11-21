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
          {
            ...userInput('Fix the `bug`'),
            'content':
                '/plan is a [Slash Command]:\n'
                '<USER_REQUEST>\nFix the `bug`\n</USER_REQUEST>',
            'created_at': '2026-01-01T00:00:00Z',
          },
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
          runtimeMessage('root', 'Find the bug.'),
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

- Triggered `/plan` (Slash Command)
- Thinking: `Look first.`
- ✅ `run_command` `cat ~/a.dart`
- ✅ `edit_file` `a.dart`
- ✅ `invoke_subagent`
- ❌ `run_command` `dart test`
  ```
  …
  line 3
  line 4
  line 5
  line 6
  line 7
  ```
- Replied: `Fixed it.`

## `sub`

### Before the first request

- Message: `Find the bug.`
- ✅ `grep_search` `bug` in `lib`
- ⏳ `write_file` `a.dart`

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

    expect(formatTrajectoryReport(tree), '''
# Trajectory

## `root` (root)

No turns.

## Tool calls

No tool calls.
''');
  });

  group('quotes', () {
    /// Returns the report on a conversation that runs [command].
    String reportCommand(String command, {String? homeDirectory}) =>
        formatTrajectoryReport(
          ConversationTree(
            transcripts: [
              transcript([
                userInput('Go'),
                modelCall(
                  calls: [
                    toolCall('run_command', {'CommandLine': command}),
                  ],
                ),
              ]),
            ],
          ),
          homeDirectory: homeDirectory,
        );

    test('are shortened', () {
      final tree = ConversationTree(
        transcripts: [
          transcript([userInput('${'long ' * 20}request')]),
        ],
      );

      expect(
        formatTrajectoryReport(tree),
        contains('### Turn 1: `${'long ' * 15}long…`\n'),
      );
    });

    test('are on one line', () {
      expect(
        reportCommand('cat <<EOF\n# not a heading\n- not an item\nEOF'),
        contains(
          '- ⏳ `run_command` `cat <<EOF # not a heading - not an item EOF`\n',
        ),
      );
    });

    test('are marked when empty', () {
      final tree = ConversationTree(
        transcripts: [
          transcript([userInput('')]),
        ],
      );

      expect(formatTrajectoryReport(tree), contains('### Turn 1: (empty)\n'));
    });

    test('escape file names', () {
      final tree = ConversationTree(
        transcripts: [
          transcript([
            userInput('Go'),
            modelCall(
              calls: [
                toolCall('read_file', {'Path': '/a/__init__.py'}),
              ],
            ),
          ]),
        ],
      );

      expect(
        formatTrajectoryReport(tree),
        contains('- ⏳ `read_file` `__init__.py`\n'),
      );
    });

    test('shorten only whole home directories', () {
      String shortened(String command, String home) =>
          RegExp(r'`run_command` `(.*)`')
              .firstMatch(reportCommand(command, homeDirectory: home))![1]!;

      expect(shortened('ls /home/me /home/me/a', '/home/me'), 'ls ~ ~/a');
      expect(shortened('ls /home/me/a', '/home/me/'), 'ls ~/a');
      expect(
        shortened('ls /home/meg/a /var/home/me/b', '/home/me'),
        'ls /home/meg/a /var/home/me/b',
      );
      expect(shortened('ls /home/me', ''), 'ls /home/me');
      expect(shortened(r'ls \home\me\a', '/home/me'), r'ls \home\me\a');
    });

    test('shorten Windows home directories with either separator, in any '
        'case', () {
      String shortened(String command) => RegExp(
        r'`run_command` `(.*)`',
      ).firstMatch(reportCommand(command, homeDirectory: r'C:\Users\me'))![1]!;

      expect(shortened(r'type C:\Users\me\a.dart'), r'type ~\a.dart');
      expect(shortened('cat C:/Users/me/a.dart'), 'cat ~/a.dart');
      expect(shortened(r'dir c:\users\me\a.dart'), r'dir ~\a.dart');
      expect(
        shortened(r'type C:\Users\meg\a.dart'),
        r'type C:\Users\meg\a.dart',
      );
    });
  });

  test('fences failure output that contains fences', () {
    final tree = ConversationTree(
      transcripts: [
        transcript([
          userInput('Go'),
          modelCall(calls: [toolCall('read_file')]),
          toolResult('Error: bad\n```\nquoted\n```'),
        ]),
      ],
    );

    expect(
      formatTrajectoryReport(tree),
      contains('  ````\n  Error: bad\n  ```\n  quoted\n  ```\n  ````\n'),
    );
  });

  test('reports a single tool without a total', () {
    final tree = ConversationTree(
      transcripts: [
        transcript([
          userInput('Go'),
          modelCall(calls: [toolCall('read_file'), toolCall('read_file')]),
        ]),
      ],
    );

    final report = formatTrajectoryReport(tree);
    expect(report, contains('| read_file | 2 | 0 | – |\n'));
    expect(report, isNot(contains('Total')));
    expect(
      report,
      contains(
        "2 calls hadn't finished, so they aren't counted in success "
        'rates.',
      ),
    );
  });

  test('formats durations', () {
    String duration(String end) =>
        RegExp(r'### Turn 1: `Go` \((.*)\)').firstMatch(
          formatTrajectoryReport(
            ConversationTree(
              transcripts: [
                transcript([
                  {...userInput('Go'), 'created_at': '2026-01-01T00:00:00Z'},
                  {...modelCall(), 'created_at': '2026-01-01T$end'},
                ]),
              ],
            ),
          ),
        )![1]!;

    expect(duration('00:00:45Z'), '45s');
    expect(duration('00:02:00Z'), '2m 0s');
    expect(duration('01:00:05Z'), '1h 0m 5s');
  });
}
