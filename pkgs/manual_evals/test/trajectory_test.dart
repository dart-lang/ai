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
          modelCall(tools: ['read_file']),
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

    test('puts model calls before the first request in their own turn', () {
      final trajectory = summarizeTrajectory(
        transcript([systemMessage('Prompt'), modelCall(), userInput('Later')]),
      );

      expect(
        [for (final turn in trajectory.turns) turn.request],
        [null, 'Later'],
      );
    });

    test('has no turns when there are no requests or model calls', () {
      expect(
        summarizeTrajectory(transcript([systemMessage('Prompt')])).turns,
        isEmpty,
      );
    });

    test('measures each turn from its first to its last recorded step', () {
      final trajectory = summarizeTrajectory(
        transcript([
          {...userInput('Go'), 'created_at': '2026-01-01T00:00:00Z'},
          {...modelCall(), 'created_at': '2026-01-01T00:01:05Z'},
          modelCall(),
          {...userInput('Again'), 'created_at': '2026-01-01T00:02:00Z'},
          userInput('Untimed'),
        ]),
      );

      expect(
        [for (final turn in trajectory.turns) turn.duration],
        [const Duration(minutes: 1, seconds: 5), Duration.zero, null],
      );
    });

    test(
      'records explicit triggers, the first thought, and the last reply',
      () {
        final trajectory = summarizeTrajectory(
          transcript([
            {
              ...userInput('/plan Do it'),
              'content':
                  '/plan is a [Slash Command]:\n'
                  'review is a [Skill]:\n'
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
        expect(turn.triggers, [
          (kind: 'Slash Command', name: '/plan'),
          (kind: 'Skill', name: 'review'),
        ]);
        expect(turn.thinking, 'First idea.');
        expect(turn.reply, 'Done now');
      },
    );

    group('tool calls', () {
      TrajectoryToolCall summarize(
        Map<String, Object?> call,
        List<Map<String, Object?>> answers,
      ) => summarizeTrajectory(
        transcript([
          userInput('Go'),
          modelCall(calls: [call]),
          ...answers,
        ]),
      ).toolCalls.single;

      test('succeed when their result is done', () {
        final call = summarize(toolCall('read_file', {'Path': '/a/b.dart'}), [
          toolResult('contents'),
        ]);

        expect(call.tool, 'read_file');
        expect(call.path, '/a/b.dart');
        expect(call.outcome, ToolOutcome.succeeded);
        expect(call.failureOutput, isNull);
      });

      test('fail when their result is an error', () {
        for (final answer in [
          {...toolResult('Not found'), 'status': 'ERROR'},
          {...toolResult(''), 'error': 'Not found'},
          toolResult('Error: Not found'),
          {'type': 'ERROR_MESSAGE', 'source': 'SYSTEM', 'content': 'Not found'},
        ]) {
          final call = summarize(toolCall('read_file'), [answer]);

          expect(call.outcome, ToolOutcome.failed, reason: '$answer');
          expect(call.failureOutput, contains('Not found'), reason: '$answer');
        }
      });

      test('are unfinished without a final result', () {
        expect(
          summarize(toolCall('run_command'), []).outcome,
          ToolOutcome.unfinished,
        );
        expect(
          summarize(toolCall('run_command'), [
            {...toolResult('Running in the background'), 'status': 'RUNNING'},
          ]).outcome,
          ToolOutcome.unfinished,
        );
      });

      test('that run commands fail when the command fails', () {
        final command = toolCall('run_command', {'CommandLine': 'dart test'});

        final failed = summarize(command, [
          toolResult(
            'Created At: 2026-01-01T00:00:00Z\n'
            'Command exited with code 1.\n'
            '\n'
            'Command output:\n'
            'Some tests failed.\n',
          ),
        ]);
        expect(failed.command, 'dart test');
        expect(failed.outcome, ToolOutcome.failed);
        expect(failed.failureOutput, 'Some tests failed.');

        expect(
          summarize(command, [
            {...toolResult(''), 'type': 'RUN_COMMAND', 'exit_code': 2},
          ]).outcome,
          ToolOutcome.failed,
        );
        expect(
          summarize(command, [
            toolResult('The command exited with code 0.\nOutput:\nAll passed.'),
          ]).outcome,
          ToolOutcome.succeeded,
        );
      });

      test('that read files ignore exit codes in the file', () {
        expect(
          summarize(toolCall('read_file', {'Path': 'log.txt'}), [
            toolResult('Command exited with code 1.'),
          ]).outcome,
          ToolOutcome.succeeded,
        );
      });

      test('record their query and path', () {
        final call = summarize(
          toolCall('grep_search', {'Query': 'Turn', 'SearchPath': '/a/b'}),
          [toolResult('matches')],
        );

        expect(call.query, 'Turn');
        expect(call.path, '/a/b');
      });

      test('read JSON-encoded arguments', () {
        final call = summarize(
          {'name': 'run_command', 'args': '{"CommandLine": "ls"}'},
          [toolResult('Command exited with code 0.')],
        );

        expect(call.command, 'ls');
      });

      test('name MCP tools called through call_mcp_tool after the tool', () {
        final call = summarize(
          toolCall('call_mcp_tool', {
            'ServerName': 'github',
            'ToolName': 'search_issues',
          }),
          [toolResult('[]')],
        );

        expect(call.tool, 'mcp_github_search_issues');
      });

      test('modify files when they edit a file and do not fail', () {
        TrajectoryToolCall edit(String tool, ToolOutcome outcome) =>
            TrajectoryToolCall(tool: tool, outcome: outcome, path: 'a.dart');

        expect(edit('write_file', ToolOutcome.succeeded).modifiesFile, isTrue);
        expect(edit('edit_file', ToolOutcome.unfinished).modifiesFile, isTrue);
        expect(edit('edit_file', ToolOutcome.failed).modifiesFile, isFalse);
        expect(edit('read_file', ToolOutcome.succeeded).modifiesFile, isFalse);
        expect(
          const TrajectoryToolCall(
            tool: 'write_file',
            outcome: ToolOutcome.succeeded,
          ).modifiesFile,
          isFalse,
        );
      });
    });

    test('matches results to calls across interleaved steps', () {
      final trajectory = summarizeTrajectory(
        transcript([
          userInput('Go'),
          modelCall(tools: ['read_file', 'bad_call', 'run_command']),
          toolResult('contents'),
          {'type': 'ERROR_MESSAGE', 'source': 'SYSTEM', 'content': 'Unknown'},
          systemMessage('A background task finished.'),
          {...toolResult('Command exited with code 3.'), 'exit_code': 3},
        ]),
      );

      expect(
        [for (final call in trajectory.toolCalls) call.outcome],
        [ToolOutcome.succeeded, ToolOutcome.failed, ToolOutcome.failed],
      );
    });
  });
}
