// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:manual_evals/manual_evals.dart';
import 'package:test/test.dart';

import 'steps.dart';

void main() {
  group('summarizeTrajectory', () {
    test('splits the conversation into turns at each request', () {
      final trajectory = summarizeTrajectory(
        transcript([
          userInput('First'),
          modelCall(calls: [toolCall('read_file')]),
          toolResult('contents'),
          userInput('Second'),
          modelCall(),
        ]),
      );

      expect(trajectory.conversationId, 'conv');
      expect(
        [for (final turn in trajectory.turns) turn.request],
        ['First', 'Second'],
      );
      expect(trajectory.turns.first.toolCalls.single.tool, 'read_file');
      expect(trajectory.turns.last.toolCalls, isEmpty);
    });

    test('labels model calls before the first request with the first '
        'message', () {
      final trajectory = summarizeTrajectory(
        transcript([
          systemMessage('The following customizations were discovered.'),
          runtimeMessage('parent', 'Review this\nchange.'),
          modelCall(),
          userInput('Later'),
        ]),
      );

      expect(
        [
          for (final turn in trajectory.turns)
            (turn.request, turn.initialMessage),
        ],
        [(null, 'Review this change.'), ('Later', null)],
      );
    });

    test('has no turns when there are no requests or model calls', () {
      expect(
        summarizeTrajectory(transcript([systemMessage('Prompt')])).turns,
        isEmpty,
      );
    });

    test('measures each turn from its earliest to its latest step', () {
      final trajectory = summarizeTrajectory(
        transcript([
          {...userInput('Go'), 'created_at': '2026-01-01T00:00:00Z'},
          {...modelCall(), 'created_at': '2026-01-01T00:10:00Z'},
          {...modelCall(), 'created_at': '2026-01-01T00:05:00Z'},
          modelCall(),
          {...userInput('Again'), 'created_at': '2026-01-01T00:20:00Z'},
          userInput('Untimed'),
        ]),
      );

      expect(
        [for (final turn in trajectory.turns) turn.duration],
        [const Duration(minutes: 10), Duration.zero, null],
      );
    });

    test(
      'records explicit triggers, the first thought, and the last reply',
      () {
        final trajectory = summarizeTrajectory(
          transcript([
            {
              ...userInput('Do it'),
              'content':
                  '/plan is a [Slash Command]:\n'
                  '<USER_REQUEST>\nDo it\n</USER_REQUEST>',
            },
            modelCall(
              thinking: 'First idea.  More detail!',
              content: 'Working',
            ),
            modelCall(thinking: 'Second idea.', content: 'Done\n  now'),
            modelCall(content: '  '),
          ]),
        );

        final turn = trajectory.turns.single;
        expect(turn.request, 'Do it');
        expect(turn.triggers, [(kind: 'Slash Command', name: '/plan')]);
        expect(turn.thinking, 'First idea.');
        expect(turn.reply, 'Done now');
      },
    );

    test("doesn't end the first thought at an abbreviation", () {
      String? thinking(String text) => summarizeTrajectory(
        transcript([userInput('Go'), modelCall(thinking: text)]),
      ).turns.single.thinking;

      expect(
        thinking('Use a tool, e.g. grep. Then stop.'),
        'Use a tool, '
        'e.g. grep.',
      );
      expect(thinking('Done? Yes.'), 'Done?');
      expect(thinking('  '), isNull);
    });

    test('matches results to calls across interleaved steps', () {
      final trajectory = summarizeTrajectory(
        transcript([
          userInput('Go'),
          modelCall(
            calls: [
              toolCall('read_file'),
              toolCall('bad_call'),
              toolCall('run_command'),
            ],
          ),
          toolResult('contents'),
          errorMessage('Unknown tool'),
          systemMessage('A notice.'),
          {...toolResult('Command exited with code 3.'), 'exit_code': 3},
        ]),
      );

      expect(
        [for (final call in trajectory.toolCalls) call.outcome],
        [
          ToolCallOutcome.succeeded,
          ToolCallOutcome.failed,
          ToolCallOutcome.failed,
        ],
      );
    });
  });

  group('tool calls', () {
    TrajectoryToolCall summarize(
      Object? call,
      List<Map<String, Object?>> answers,
    ) => summarizeTrajectory(
      transcript([
        userInput('Go'),
        modelCall(calls: [call]),
        ...answers,
      ]),
    ).toolCalls.single;

    final ls = toolCall('run_command', {'CommandLine': 'ls'});

    test('succeed when their result is done or records no status', () {
      final call = summarize(toolCall('read_file', {'Path': '/a/b.dart'}), [
        {...toolResult('contents'), 'status': 'DONE'},
      ]);

      expect(call.tool, 'read_file');
      expect(call.path, '/a/b.dart');
      expect(call.outcome, ToolCallOutcome.succeeded);
      expect(call.failureOutput, isNull);
      expect(
        summarize(toolCall('read_file'), [toolResult('contents')]).outcome,
        ToolCallOutcome.succeeded,
      );
    });

    test('fail when their result is an error', () {
      for (final answer in [
        {...toolResult('Not found'), 'status': 'ERROR'},
        {...toolResult(''), 'error': 'Not found'},
        toolResult('Error: Not found'),
        errorMessage('Not found'),
      ]) {
        final call = summarize(toolCall('read_file'), [answer]);

        expect(call.outcome, ToolCallOutcome.failed, reason: '$answer');
        expect(call.failureOutput, contains('Not found'), reason: '$answer');
      }
      expect(
        summarize(ls, [
          {...toolResult('Command exited with code 0.'), 'status': 'ERROR'},
        ]).outcome,
        ToolCallOutcome.failed,
      );
    });

    test('are unfinished without a final result', () {
      expect(summarize(ls, []).outcome, ToolCallOutcome.unfinished);
      for (final status in ['RUNNING', 'CANCELED', 'INTERRUPTED']) {
        expect(
          summarize(ls, [
            {...toolResult('Partial output'), 'status': status},
          ]).outcome,
          ToolCallOutcome.unfinished,
          reason: status,
        );
      }
    });

    group('that run commands', () {
      test('fail when the command exits with a nonzero code', () {
        final failed = summarize(ls, [
          toolResult(
            'Created At: 2026-01-01T00:00:00Z\n'
            'Completed At: 2026-01-01T00:00:01Z\n'
            'Command exited with code 1.\n'
            '\n'
            'There were sandbox errors that may or may not be related.\n'
            '\n'
            'Command output:\n'
            'Some tests failed.\n',
          ),
        ]);

        expect(failed.command, 'ls');
        expect(failed.outcome, ToolCallOutcome.failed);
        expect(failed.failureOutput, 'Some tests failed.');

        for (final answer in [
          {...toolResult(''), 'type': 'RUN_COMMAND', 'exit_code': 2},
          toolResult('Command exited with code -1.'),
        ]) {
          expect(
            summarize(ls, [answer]).outcome,
            ToolCallOutcome.failed,
            reason: '$answer',
          );
        }
      });

      test('succeed when the command exits with code 0', () {
        expect(
          summarize(ls, [
            toolResult('The command exited with code 0.\nOutput:\nAll passed.'),
          ]).outcome,
          ToolCallOutcome.succeeded,
        );
      });

      test('strip the result header from the failure output', () {
        expect(
          summarize(ls, [
            toolResult(
              'Created At: 2026-01-01T00:00:00Z\n'
              'Command exited with code 2.\n'
              'ls: x: No such file',
            ),
          ]).failureOutput,
          'ls: x: No such file',
        );
      });

      test('ignore exit codes in the output', () {
        expect(
          summarize(ls, [
            toolResult(
              'Created At: 2026-01-01T00:00:00Z\n'
              'Command output:\n'
              'Command exited with code 1.',
            ),
          ]).outcome,
          ToolCallOutcome.succeeded,
        );
      });

      test('read the exit code of truncated output', () {
        expect(
          summarize(ls, [
            toolResult(
              'Created At: 2026-01-01T00:00:00Z\n'
              "The tool's output was truncated due to being too long. "
              'Here is a preview with the middle of the output truncated:\n'
              'Command exited with code 1.\n'
              '\n'
              'Command output:\n'
              'start\n<truncated 100 bytes>\nend',
            ),
          ]).outcome,
          ToolCallOutcome.failed,
        );
      });
    });

    test("that don't run commands ignore exit codes in their result", () {
      expect(
        summarize(toolCall('read_file', {'Path': 'log.txt'}), [
          toolResult('Command exited with code 1.'),
        ]).outcome,
        ToolCallOutcome.succeeded,
      );
    });

    group('in background tasks', () {
      const taskId = 'conv/task-1';
      final started = {
        ...toolResult(
          'Created At: 2026-01-01T00:00:00Z\n'
          'Tool is running as a background task with task id: $taskId\n'
          'Task Description: ls\n'
          'Log output:\n',
        ),
        'status': 'RUNNING',
      };

      Map<String, Object?> ended(String how, String result) => runtimeMessage(
        taskId,
        'Task id "$taskId" $how with result:\n$result\n'
        'Log: file:///logs/task-1.log',
      );

      test('take the outcome of the final result', () {
        expect(
          summarize(ls, [
            started,
            ended('finished', 'Command exited with code 0.'),
          ]).outcome,
          ToolCallOutcome.succeeded,
        );

        final failed = summarize(ls, [
          started,
          ended(
            'finished',
            'Command exited with code 3.\n\nCommand output:\nbuild failed',
          ),
        ]);
        expect(failed.outcome, ToolCallOutcome.failed);
        expect(failed.failureOutput, 'build failed');

        expect(
          summarize(ls, [
            started,
            ended('failed', 'Tool execution failed'),
          ]).failureOutput,
          'Tool execution failed',
        );
      });

      test('are unfinished until they report a final result', () {
        expect(summarize(ls, [started]).outcome, ToolCallOutcome.unfinished);
        expect(
          summarize(ls, [
            started,
            ended('was canceled', 'Tool execution was canceled'),
          ]).outcome,
          ToolCallOutcome.unfinished,
        );
      });

      test("that don't run commands succeed when they finish", () {
        expect(
          summarize(toolCall('schedule'), [
            started,
            ended('finished', 'Timer fired.'),
          ]).outcome,
          ToolCallOutcome.succeeded,
        );
      });
    });

    test('record their query and path', () {
      final call = summarize(
        toolCall('grep_search', {'Query': 'Turn', 'SearchPath': '/a/b'}),
        [toolResult('matches')],
      );

      expect(call.query, 'Turn');
      expect(call.path, '/a/b');
    });

    test('prefer the Path argument to other paths', () {
      expect(
        summarize(
          toolCall('view', {'AbsolutePath': '/abs', 'Path': '/path'}),
          [],
        ).path,
        '/path',
      );
    });

    test('read JSON-encoded arguments', () {
      expect(
        summarize(
          {'name': 'run_command', 'args': '{"CommandLine": "ls"}'},
          [toolResult('Command exited with code 0.')],
        ).command,
        'ls',
      );
    });

    test('ignore malformed arguments', () {
      for (final args in ['{not json', '["a list"]', 42]) {
        final call = summarize({'name': 'run_command', 'args': args}, []);

        expect(call.tool, 'run_command', reason: '$args');
        expect(call.command, isNull, reason: '$args');
      }
    });

    test('are named (unknown) when malformed', () {
      expect(summarize('malformed', []).tool, '(unknown)');
    });

    test('name MCP tools called through call_mcp_tool after the tool', () {
      expect(
        summarize(
          toolCall('call_mcp_tool', {
            'ServerName': 'github',
            'ToolName': 'search_issues',
          }),
          [],
        ).tool,
        'mcp_github_search_issues',
      );
      expect(
        summarize(toolCall('call_mcp_tool', {'ServerName': 'github'}), []).tool,
        'call_mcp_tool',
      );
    });

    test('modify files when they edit a file and do not fail', () {
      TrajectoryToolCall edit(String tool, ToolCallOutcome outcome) =>
          TrajectoryToolCall(tool: tool, outcome: outcome, path: 'a.dart');

      expect(
        edit('write_file', ToolCallOutcome.succeeded).modifiesFile,
        isTrue,
      );
      expect(
        edit('edit_file', ToolCallOutcome.unfinished).modifiesFile,
        isTrue,
      );
      expect(edit('edit_file', ToolCallOutcome.failed).modifiesFile, isFalse);
      expect(
        edit('read_file', ToolCallOutcome.succeeded).modifiesFile,
        isFalse,
      );
      expect(
        const TrajectoryToolCall(
          tool: 'write_file',
          outcome: ToolCallOutcome.succeeded,
        ).modifiesFile,
        isFalse,
      );
    });
  });
}
