// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:manual_evals/manual_evals.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  group('searchLocations', () {
    List<String> searchLocations(Map<String, String> environment) =>
        AntigravityTranscriptSource(environment: environment).searchLocations;

    String brain(String app) => p.join(d.sandbox, '.gemini', app, 'brain');

    test('finds every ~/.gemini/<app>/brain directory, sorted', () async {
      await d.dir('.gemini', [
        d.dir('zeta', [d.dir('brain')]),
        d.dir('alpha', [d.dir('brain')]),
        d.dir('config'),
        d.file('settings.json', '{}'),
      ]).create();

      expect(searchLocations({'HOME': d.sandbox}), [
        brain('alpha'),
        brain('zeta'),
      ]);
    });

    test(
      'follows symlinked app directories',
      () async {
        await d.dir('elsewhere', [d.dir('brain')]).create();
        await d.dir('.gemini').create();
        Link(
          p.join(d.sandbox, '.gemini', 'linked'),
        ).createSync(p.join(d.sandbox, 'elsewhere'));

        expect(searchLocations({'HOME': d.sandbox}), [brain('linked')]);
      },
      skip: Platform.isWindows ? 'Symlinks need privileges on Windows' : false,
    );

    test('falls back to USERPROFILE when HOME is unset or blank', () async {
      await d.dir('.gemini', [
        d.dir('app', [d.dir('brain')]),
      ]).create();

      expect(searchLocations({'USERPROFILE': d.sandbox}), [brain('app')]);
      expect(searchLocations({'HOME': ' ', 'USERPROFILE': d.sandbox}), [
        brain('app'),
      ]);
    });

    test('puts the app data directory first, without duplicates', () async {
      await d.dir('.gemini', [
        d.dir('alpha', [d.dir('brain')]),
        d.dir('beta', [d.dir('brain')]),
      ]).create();

      expect(
        searchLocations({
          'HOME': d.sandbox,
          AntigravityTranscriptSource.appDataDirEnvironmentVariable: p.join(
            d.sandbox,
            '.gemini',
            'beta',
          ),
        }),
        [brain('beta'), brain('alpha')],
      );
    });

    test('includes an app data directory outside the home directory', () {
      final appDataDir = p.join(d.sandbox, 'elsewhere', 'agent');

      expect(
        searchLocations({
          'HOME': d.sandbox,
          AntigravityTranscriptSource.appDataDirEnvironmentVariable: appDataDir,
        }),
        [p.join(appDataDir, 'brain')],
      );
    });

    test('is empty when nothing is found', () {
      expect(searchLocations({}), isEmpty);
      expect(searchLocations({'HOME': d.sandbox}), isEmpty);
    });

    test('skips an unreadable ~/.gemini directory', () async {
      await d.dir('.gemini', [
        d.dir('app', [d.dir('brain')]),
      ]).create();
      final gemini = p.join(d.sandbox, '.gemini');
      Process.runSync('chmod', ['000', gemini]);
      addTearDown(() => Process.runSync('chmod', ['755', gemini]));

      expect(searchLocations({'HOME': d.sandbox}), isEmpty);
    }, skip: Platform.isWindows ? 'Uses chmod' : false);

    test('uses only the override environment variable when set', () async {
      await d.dir('.gemini', [
        d.dir('app', [d.dir('brain')]),
      ]).create();
      final separator = Platform.isWindows ? ';' : ':';

      expect(
        searchLocations({
          'HOME': d.sandbox,
          AntigravityTranscriptSource.appDataDirEnvironmentVariable: 'ignored',
          AntigravityTranscriptSource.rootsEnvironmentVariable: [
            'a',
            '',
            ' b ',
            p.join('a', '.'),
          ].join(separator),
        }),
        ['a', 'b'],
      );
    });

    test('cannot be modified', () {
      final roots = [d.sandbox];
      final source = AntigravityTranscriptSource(roots: roots);

      expect(source.searchLocations.clear, throwsUnsupportedError);
      roots.clear();
      expect(source.searchLocations, [d.sandbox]);
    });
  });

  group('currentConversationId', () {
    String? currentConversationId(Map<String, String> environment) =>
        AntigravityTranscriptSource(
          environment: environment,
        ).currentConversationId;

    test('reads the conversation ID environment variable', () {
      expect(
        currentConversationId({
          AntigravityTranscriptSource.conversationIdEnvironmentVariable: ' id ',
        }),
        'id',
      );
    });

    test('is null when the variable is unset or blank', () {
      expect(currentConversationId({}), isNull);
      expect(
        currentConversationId({
          AntigravityTranscriptSource.conversationIdEnvironmentVariable: ' ',
        }),
        isNull,
      );
    });
  });

  group('loadTranscript', () {
    Future<String?> pathOf(String conversationId, List<String> roots) async =>
        (await AntigravityTranscriptSource(
          roots: roots,
        ).loadTranscript(conversationId))?.path;

    test('prefers a full transcript in any root', () async {
      await d.dir('first', [
        _transcriptDir('conv', <Object?>[], fileName: 'transcript.jsonl'),
      ]).create();
      await d.dir('second', [_transcriptDir('conv', <Object?>[])]).create();
      final first = p.join(d.sandbox, 'first');
      final second = p.join(d.sandbox, 'second');

      expect(
        await pathOf('conv', [first, second]),
        p.join(_logsDir(second, 'conv'), 'transcript_full.jsonl'),
      );
    });

    test('searches roots in order', () async {
      await d.dir('first', [_transcriptDir('conv', <Object?>[])]).create();
      await d.dir('second', [_transcriptDir('conv', <Object?>[])]).create();
      final first = p.join(d.sandbox, 'first');

      expect(
        await pathOf('conv', [first, p.join(d.sandbox, 'second')]),
        p.join(_logsDir(first, 'conv'), 'transcript_full.jsonl'),
      );
    });

    test('falls back to an abbreviated transcript', () async {
      await _transcriptDir('conv', [
        {
          'step_index': 0,
          'type': 'PLANNER_RESPONSE',
          'source': 'MODEL',
          'tool_calls': [
            {
              'name': 'run_command',
              'args': {'CommandLine': '"ls"'},
            },
          ],
        },
      ], fileName: 'transcript.jsonl').create();

      final transcript = await AntigravityTranscriptSource(
        roots: [d.sandbox],
      ).loadTranscript('conv');

      expect(
        transcript?.path,
        p.join(_logsDir(d.sandbox, 'conv'), 'transcript.jsonl'),
      );
      expect(transcript?.steps.single.toolCallNames, ['run_command']);
    });

    test('finds transcripts in auto-detected roots', () async {
      await d.dir('.gemini', [
        d.dir('app', [
          d.dir('brain', [_transcriptDir('conv', <Object?>[])]),
        ]),
      ]).create();

      final transcript = await AntigravityTranscriptSource(
        environment: {'HOME': d.sandbox},
      ).loadTranscript('conv');

      expect(transcript?.conversationId, 'conv');
    });

    test('returns null when the transcript is missing', () async {
      expect(await pathOf('missing', [d.sandbox]), isNull);
    });

    test('returns null for invalid conversation IDs', () async {
      await _transcriptDir('conv', <Object?>[]).create();
      final roots = [p.join(d.sandbox, 'brain')];

      for (final id in ['../conv', p.join('..', 'conv'), '', 'a b']) {
        expect(await pathOf(id, roots), isNull, reason: id);
      }
    });

    test('skips blank, malformed, and non-object lines', () async {
      await _transcriptDir(
        'conv',
        [
          '{"step_index": 0, "type": "USER_INPUT"}',
          'corrupted json line {',
          '',
          '[1, 2, 3]',
          '{"step_index": 1, "type": "PLANNER_RESPONSE", "content": {}}',
        ].join('\n'),
      ).create();

      final transcript = await AntigravityTranscriptSource(
        roots: [d.sandbox],
      ).loadTranscript('conv');

      expect(
        transcript,
        isA<ConversationTranscript>()
            .having((t) => t.conversationId, 'conversationId', 'conv')
            .having((t) => t.steps.map((s) => s.type), 'step types', [
              StepType.userInput,
              StepType.plannerResponse,
            ]),
      );
    });

    test('handles CRLF line endings and invalid UTF-8', () async {
      await _transcriptDir('conv', [
        ...utf8.encode('{"step_index": 0, "content": "caf\u00e9"}\r\n'),
        ...utf8.encode('{"step_index": 1, "content": "'),
        0xC3, // A truncated two-byte character.
        ...utf8.encode('"}\r\n'),
      ]).create();

      final steps =
          (await AntigravityTranscriptSource(
            roots: [d.sandbox],
          ).loadTranscript('conv'))!.steps;

      expect(steps.map((s) => s.content), ['caf\u00e9', '\uFFFD']);
    });

    test('sorts steps by index and keeps the last copy of each', () async {
      await _transcriptDir('conv', [
        {'step_index': 0, 'content': 'zero'},
        {'step_index': 2, 'content': 'two'},
        {'content': 'unindexed'},
        {'step_index': 1, 'content': 'one'},
        {'step_index': 2, 'content': 'two, updated'},
      ]).create();

      final steps =
          (await AntigravityTranscriptSource(
            roots: [d.sandbox],
          ).loadTranscript('conv'))!.steps;

      expect(steps.map((s) => s.content), [
        'zero',
        'one',
        'two, updated',
        'unindexed',
      ]);
    });
  });

  group('subagent detection', () {
    Future<List<String>> subagentIdsOf(List<Map<String, Object?>> steps) async {
      await _transcriptDir('conv', [
        for (final (index, step) in steps.indexed)
          {'step_index': index, ...step},
      ]).create();
      final transcript = await AntigravityTranscriptSource(
        roots: [d.sandbox],
      ).loadTranscript('conv');
      return transcript!.subagentIds;
    }

    test('finds subagents in invoke_subagent results', () async {
      expect(
        await subagentIdsOf([
          _calls(['invoke_subagent']),
          _spawnResult(['sub-1']),
          _calls(['invoke_subagent']),
          _spawnResult(['sub-2', 'sub-1'], type: 'INVOKE_SUBAGENT'),
        ]),
        ['sub-1', 'sub-2'],
      );
    });

    test('ignores invoke_subagent results without the banner', () async {
      expect(
        await subagentIdsOf([
          _calls(['invoke_subagent']),
          _result('Error: {"conversationId": "not-created"}'),
        ]),
        isEmpty,
      );
    });

    test('ignores conversation IDs outside subagent tool results', () async {
      const mention = '{"conversationId": "not-a-subagent"}';
      expect(
        await subagentIdsOf([
          {'type': 'USER_INPUT', 'source': 'USER_EXPLICIT', 'content': mention},
          {
            ..._calls(['run_command']),
            'content': mention,
          },
          _result(mention, type: 'RUN_COMMAND'),
          {'type': 'SYSTEM_MESSAGE', 'source': 'SYSTEM', 'content': mention},
        ]),
        isEmpty,
      );
    });

    test('matches results to tool calls in order', () async {
      expect(
        await subagentIdsOf([
          _calls(['read_file', 'invoke_subagent', 'run_command']),
          _spawnResult(['in-read-file-output'], type: 'VIEW_FILE'),
          {'type': 'SYSTEM_MESSAGE', 'source': 'SYSTEM'},
          {'type': 'EPHEMERAL_MESSAGE', 'source': 'MODEL'},
          _spawnResult(['sub-1']),
          _spawnResult(['in-command-output'], type: 'RUN_COMMAND'),
          _spawnResult(['extra-result']),
        ]),
        ['sub-1'],
      );
    });

    test('accounts for calls answered by an error message', () async {
      expect(
        await subagentIdsOf([
          _calls(['run_command', 'invoke_subagent']),
          {'type': 'ERROR_MESSAGE', 'source': 'SYSTEM'},
          _spawnResult(['sub-1']),
        ]),
        ['sub-1'],
      );
    });

    test('pairs results by step index, not line order', () async {
      await _transcriptDir('conv', [
        {
          'step_index': 0,
          ..._calls(['view_file']),
        },
        {'step_index': 1, ..._result('{"conversationId": "in-file"}')},
        {
          'step_index': 3,
          ..._spawnResult(['sub-1']),
        },
        {
          'step_index': 2,
          ..._calls(['invoke_subagent']),
        },
      ]).create();

      final transcript = await AntigravityTranscriptSource(
        roots: [d.sandbox],
      ).loadTranscript('conv');

      expect(transcript!.subagentIds, ['sub-1']);
    });

    test('finds workflow agents in run_workflow results', () async {
      expect(
        await subagentIdsOf([
          _calls(['run_workflow']),
          _result(
            _workflowResult([
              '- [phase] Review',
              '- [agent:self] Review a.dart: done (wf-1): "OK"',
              '- [agent:reviewer] Check (b.dart): error (wf-2): Error (x): y',
              '- [agent:self] Sample: canceled (wf-3)',
              '- [agent:self] Lead: done, turn 2 (wf-4): "Summary"',
              '- [agent:self] Waiting: idle (wf-5)',
              '- [agent:self] Busy: running (wf-6)',
              '- not an agent line: done (not-an-agent)',
            ]),
          ),
        ]),
        ['wf-1', 'wf-2', 'wf-3', 'wf-4', 'wf-5', 'wf-6'],
      );
    });

    test('ignores JSON conversation IDs in run_workflow results', () async {
      expect(
        await subagentIdsOf([
          _calls(['run_workflow']),
          _result(
            '${_workflowResult(['- [agent:self] A: done (wf-1)'])}\n'
            'Output:\n{"conversationId": "printed-by-script"}',
          ),
        ]),
        ['wf-1'],
      );
    });

    test('follows subagent tools that finish in the background', () async {
      expect(
        await subagentIdsOf([
          _calls(['run_command', 'run_workflow', 'invoke_subagent']),
          _backgroundResult('conv/task-1'),
          _backgroundResult('conv/task-2'),
          _backgroundResult('conv/task-3'),
          _taskMessages({
            'conv/task-1': _workflowResult([
              '- [agent:self] From a command: done (in-command-output)',
            ]),
          }),
          {..._calls([]), 'content': 'Waiting for the tasks.'},
          _taskMessages({
            'other/task-2': _workflowResult([
              '- [agent:self] Another task: done (other-task)',
            ]),
            'conv/task-2': _workflowResult([
              '- [agent:self] Sample ping: done (wf-1): "ping"',
              '- [agent:self] Sample pong: done (wf-2): "pong"',
            ]),
            'conv/task-12': _workflowResult([
              '- [agent:self] Similar task ID: done (similar-task)',
            ]),
            'conv/task-3':
                'Created the following subagent:\n'
                '{"conversationId": "sub-1"}',
          }),
        ]),
        ['wf-1', 'wf-2', 'sub-1'],
      );
    });

    test('reads completed results that mention a background task', () async {
      expect(
        await subagentIdsOf([
          _calls(['run_workflow']),
          _result(
            _workflowResult([
              '- [agent:self] Explain: done (wf-1): "It printed:',
              'Tool is running as a background task with task id: x/task-1',
              '"',
              '- [agent:self] Other: done (wf-2)',
            ]),
          ),
        ]),
        ['wf-1', 'wf-2'],
      );
    });

    test('reports subagents in the order their results arrive', () async {
      expect(
        await subagentIdsOf([
          _calls(['run_workflow']),
          _backgroundResult('conv/task-1'),
          _taskMessages({
            'conv/task-1': _workflowResult(['- [agent:self] A: done (wf-1)']),
          }),
          _calls(['invoke_subagent']),
          _spawnResult(['sub-1']),
        ]),
        ['wf-1', 'sub-1'],
      );
    });

    test('only reads the sender at the start of a task message', () async {
      expect(
        await subagentIdsOf([
          _calls(['run_workflow']),
          _backgroundResult('conv/task-1'),
          _taskMessages({
            'other/task-9':
                'Mentions sender=conv/task-1\n'
                '- [agent:self] Not ours: done (not-ours)',
          }),
        ]),
        isEmpty,
      );
    });

    test('ignores references to the conversation itself', () async {
      expect(
        await subagentIdsOf([
          _calls(['invoke_subagent']),
          _spawnResult(['conv']),
        ]),
        isEmpty,
      );
    });

    test('works with loadConversationTree', () async {
      await _transcriptDir('root', [
        _calls(['invoke_subagent']),
        _spawnResult(['sub']),
      ]).create();
      await _transcriptDir('sub', [
        {'type': 'PLANNER_RESPONSE', 'content': 'Done.'},
      ], fileName: 'transcript.jsonl').create();

      final tree = await loadConversationTree(
        'root',
        sources: [
          AntigravityTranscriptSource(roots: [d.sandbox]),
        ],
      );

      expect(tree.transcripts.map((t) => t.conversationId), ['root', 'sub']);
    });
  });

  group('warnings', () {
    Future<List<String>> warningsOf(Object contents) async {
      await _transcriptDir('conv', contents).create();
      final transcript = await AntigravityTranscriptSource(
        roots: [d.sandbox],
      ).loadTranscript('conv');
      return [for (final warning in transcript!.warnings) '$warning'];
    }

    Future<List<String>> warningsOfSteps(List<Map<String, Object?>> steps) =>
        warningsOf([
          for (final (index, step) in steps.indexed)
            {'step_index': index, ...step},
        ]);

    test('are empty for a well-formed transcript', () async {
      expect(
        await warningsOfSteps([
          _calls(['invoke_subagent', 'run_workflow']),
          _spawnResult(['sub-1']),
          _result(_workflowResult(['- [agent:self] A: done (wf-1)'])),
        ]),
        isEmpty,
      );
    });

    test(
      'report skipped lines, except a partially written last line',
      () async {
        expect(
          await warningsOf(
            [
              '{"step_index": 0}',
              'not json',
              '{"step_index": 1}',
              '{"step_index": 2, "type": "PLANN',
            ].join('\n'),
          ),
          ["conv: Skipped 1 line that isn't a transcript step."],
        );
        expect(await warningsOf('{"step_index": 0}\n{"step_'), isEmpty);
      },
    );

    test('report a transcript with no readable lines', () async {
      expect(await warningsOf('one\ntwo\n'), [
        'conv: No line is a transcript step.',
      ]);
    });

    test('ignore a transcript whose only line is partially written', () async {
      expect(await warningsOf('{"step_index": 0, "type": "USER_'), isEmpty);
    });

    test('report subagent results with no subagents', () async {
      expect(
        await warningsOfSteps([
          _calls(['invoke_subagent', 'run_workflow']),
          _result('Spawned a subagent: {"conversationId": "sub-1"}'),
          _result(_workflowResult(['- [agent:self] A: finished [wf-1]'])),
        ]),
        [
          "conv (step 1): Couldn't find the subagents in this invoke_subagent "
              'result.',
          "conv (step 2): Couldn't find the subagents in this run_workflow "
              'result.',
        ],
      );
    });

    test('report unrecognized run_workflow results', () async {
      expect(
        await warningsOfSteps([
          _calls(['run_workflow']),
          {
            ..._result(
              'Created At: 2026-10-29T23:48:50Z\n'
              'Tool is running as a background job with ID: conv/task-1',
            ),
            'status': 'RUNNING',
          },
        ]),
        [
          "conv (step 1): Couldn't find the subagents in this run_workflow "
              'result.',
        ],
      );
    });

    test('ignore results that legitimately report no subagents', () async {
      expect(
        await warningsOfSteps([
          _calls(['invoke_subagent', 'run_workflow']),
          {..._result('Error: unknown subagent type.'), 'status': 'ERROR'},
          _result(_workflowResult(['- Called 3 tools.'])),
        ]),
        isEmpty,
      );
    });

    test('ignore subagent results that are unfinished or failed', () async {
      expect(
        await warningsOfSteps([
          _calls([
            'invoke_subagent',
            'run_workflow',
            'invoke_subagent',
            'run_workflow',
            'invoke_subagent',
          ]),
          {..._result(''), 'status': 'RUNNING'},
          {
            ..._result('Created At: 2026-10-29T23:48:50Z\n'),
            'status': 'RUNNING',
          },
          {..._result('Canceled.'), 'status': 'CANCELED'},
          {..._result('Interrupted.'), 'status': 'INTERRUPTED'},
          {..._result('Error: boom'), 'status': 'ERROR'},
        ]),
        isEmpty,
      );
    });

    test('report truncated subagent results', () async {
      expect(
        await warningsOfSteps([
          _calls(['invoke_subagent', 'run_workflow']),
          {
            ..._spawnResult(['sub-1']),
            'truncated_fields': ['content'],
          },
          _backgroundResult('conv/task-1'),
          {
            ..._taskMessages({
              'conv/task-1': _workflowResult(['- [agent:self] A: done (wf-1)']),
            }),
            'truncated_fields': ['content'],
          },
        ]),
        [
          'conv (step 1): This invoke_subagent result is truncated, so '
              'subagents may be missing.',
          'conv (step 3): This run_workflow result is truncated, so '
              'subagents may be missing.',
        ],
      );
    });

    test('report background tasks that never reported a result', () async {
      expect(
        await warningsOfSteps([
          _calls(['run_workflow']),
          _backgroundResult('conv/task-1'),
        ]),
        [
          'conv (step 1): run_workflow in background task conv/task-1 never '
              'reported a result. It may still be running.',
        ],
      );
    });

    test('ignore background tasks that failed or were canceled', () async {
      String endedEarly(String taskId, String outcome, String result) =>
          '[Message] timestamp=2026-10-31T01:56:42Z sender=$taskId '
          'priority=MESSAGE_PRIORITY_HIGH content=Task id "$taskId" $outcome '
          'with result:\n$result';
      expect(
        await warningsOfSteps([
          _calls(['run_workflow', 'run_workflow']),
          _backgroundResult('conv/task-1'),
          _backgroundResult('conv/task-2'),
          {
            'type': 'SYSTEM_MESSAGE',
            'source': 'SYSTEM',
            'content': [
              endedEarly(
                'conv/task-1',
                'failed',
                'Encountered error in tool execution: workflow execution '
                    'failed (line 3): RuntimeError: boom',
              ),
              endedEarly(
                'conv/task-2',
                'was canceled',
                'Tool execution was canceled',
              ),
            ].join('\n'),
          },
        ]),
        isEmpty,
      );
    });

    test('ignore workflow results without a description or agents', () async {
      expect(
        await warningsOfSteps([
          _calls(['run_workflow']),
          _result('Workflow completed.\nThe workflow called 3 tools.'),
        ]),
        isEmpty,
      );
    });

    test('report background results with no subagents', () async {
      expect(
        await warningsOfSteps([
          _calls(['run_workflow', 'run_workflow']),
          _backgroundResult('conv/task-1'),
          _backgroundResult('conv/task-2'),
          _taskMessages({
            'conv/task-1': _workflowResult(['- [agent:self] A: finished']),
            'conv/task-2': _workflowResult(['- Called 3 tools.']),
          }),
        ]),
        [
          "conv (step 1): Couldn't find the subagents in the result of "
              'run_workflow in background task conv/task-1.',
        ],
      );
    });
  });
}

/// A `PLANNER_RESPONSE` step that calls the tools named [toolNames].
Map<String, Object?> _calls(List<String> toolNames) => {
  'type': 'PLANNER_RESPONSE',
  'source': 'MODEL',
  'tool_calls': [
    for (final name in toolNames) {'name': name, 'args': <String, Object?>{}},
  ],
};

/// A completed tool result step of [type] with [content].
Map<String, Object?> _result(String content, {String type = 'GENERIC'}) => {
  'type': type,
  'source': 'MODEL',
  'status': 'DONE',
  'content': content,
};

/// A tool result step of [type] in the format `invoke_subagent` produces,
/// reporting [conversationIds].
Map<String, Object?> _spawnResult(
  List<String> conversationIds, {
  String type = 'GENERIC',
}) {
  final plural = conversationIds.length > 1;
  final details = [
    for (final id in conversationIds)
      const JsonEncoder.withIndent('  ').convert({
        'conversationId': id,
        'logAbsoluteUri': 'file:///brain/$id/transcript.jsonl',
      }),
  ].join('\n');
  return _result(
    'Created At: 2026-10-29T23:10:52Z\n'
    'Created the following subagent${plural ? 's' : ''}:\n$details\n'
    'The subagent${plural ? 's' : ''} will send you a message when done.',
    type: type,
  );
}

/// The text of a completed `run_workflow` result with the given log [lines].
String _workflowResult(List<String> lines) =>
    'Workflow "Sample" completed.\nLogs:\n${lines.join('\n')}';

/// A tool result step for a call still running in background task [taskId].
Map<String, Object?> _backgroundResult(String taskId) => {
  ..._result(
    'Created At: 2026-10-29T23:48:50Z\n'
    'Tool is running as a background task with task id: $taskId\n'
    'Task logs are available at: file:///tmp/task.log',
  ),
  'status': 'RUNNING',
};

/// A `SYSTEM_MESSAGE` step containing a completion message from each task in
/// [resultsByTaskId].
Map<String, Object?> _taskMessages(Map<String, String> resultsByTaskId) => {
  'type': 'SYSTEM_MESSAGE',
  'source': 'SYSTEM',
  'content': [
    'The following is a <SYSTEM_MESSAGE> not actually sent by the user.',
    '<SYSTEM_MESSAGE>',
    for (final MapEntry(key: taskId, value: result) in resultsByTaskId.entries)
      '[Message] timestamp=2026-10-29T23:48:56Z sender=$taskId '
          'priority=MESSAGE_PRIORITY_HIGH content=Task id "$taskId" finished '
          'with result:\n$result\nLog: file:///tmp/task.log',
    '</SYSTEM_MESSAGE>',
  ].join('\n'),
};

/// The logs directory for [conversationId] under [root].
String _logsDir(String root, String conversationId) =>
    p.join(root, conversationId, '.system_generated', 'logs');

/// A descriptor for the directory of [conversationId], containing a
/// transcript file named [fileName].
///
/// [contents] is either a list of steps, which are written as JSONL, raw text,
/// or raw bytes.
d.Descriptor _transcriptDir(
  String conversationId,
  Object contents, {
  String fileName = 'transcript_full.jsonl',
}) => d.dir(conversationId, [
  d.dir('.system_generated', [
    d.dir('logs', [
      switch (contents) {
        final List<int> bytes => d.file(fileName, bytes),
        final String text => d.file(fileName, text),
        final List<Object?> steps => d.file(
          fileName,
          steps.map(jsonEncode).join('\n'),
        ),
        _ => throw ArgumentError.value(contents, 'contents'),
      },
    ]),
  ]),
]);
