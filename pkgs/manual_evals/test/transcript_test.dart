// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:manual_evals/manual_evals.dart';
import 'package:test/test.dart';

void main() {
  group('TranscriptStep', () {
    test('exposes every recorded field', () {
      final step = TranscriptStep({
        'step_index': 7,
        'source': 'MODEL',
        'type': 'PLANNER_RESPONSE',
        'status': 'DONE',
        'exit_code': 2,
        'error': 'boom',
        'error_code': 13,
        'created_at': '2026-10-29T23:10:48Z',
        'input_tokens': 1027,
        'cache_read_tokens': 140786,
        'output_tokens': 387,
        'content': 'c',
        'thinking': 't',
        'tool_calls': [
          {'name': 'run_command', 'args': <String, Object?>{}},
          'malformed',
          {'name': 42},
        ],
        'truncated_fields': ['content', 7],
      });

      expect(step.stepIndex, 7);
      expect(step.source, StepSource.model);
      expect(step.type, StepType.plannerResponse);
      expect(step.status, StepStatus.done);
      expect(step.exitCode, 2);
      expect(step.error, 'boom');
      expect(step.errorCode, '13');
      expect(step.createdAt, DateTime.utc(2026, 10, 29, 23, 10, 48));
      expect(step.inputTokens, 1027);
      expect(step.cacheReadTokens, 140786);
      expect(step.outputTokens, 387);
      expect(step.content, 'c');
      expect(step.thinking, 't');
      expect(step.toolCalls, hasLength(3));
      expect(step.toolCallNames, ['run_command', null, null]);
      expect(step.truncatedFields, ['content']);
    });

    test('returns defaults for missing fields', () {
      final step = TranscriptStep({});

      expect(step.stepIndex, isNull);
      expect(step.source, const StepSource(''));
      expect(step.type, const StepType(''));
      expect(step.status, const StepStatus(''));
      expect(step.exitCode, isNull);
      expect(step.error, isNull);
      expect(step.errorCode, isNull);
      expect(step.createdAt, isNull);
      expect(step.inputTokens, isNull);
      expect(step.cacheReadTokens, isNull);
      expect(step.outputTokens, isNull);
      expect(step.content, '');
      expect(step.thinking, '');
      expect(step.toolCalls, isNull);
      expect(step.toolCallNames, isEmpty);
      expect(step.truncatedFields, isEmpty);
    });

    test('returns defaults for fields of the wrong type', () {
      final step = TranscriptStep({
        'step_index': '7',
        'source': 1,
        'type': 5,
        'status': true,
        'exit_code': '2',
        'error': ['boom'],
        'error_code': {'code': 13},
        'created_at': 20261029,
        'input_tokens': '1027',
        'cache_read_tokens': null,
        'output_tokens': <Object?>[],
        'content': <String, Object?>{},
        'thinking': 3.5,
        'tool_calls': {'name': 'run_command'},
        'truncated_fields': 'content',
      });

      expect(step.stepIndex, isNull);
      expect(step.source, const StepSource(''));
      expect(step.type, const StepType(''));
      expect(step.status, const StepStatus(''));
      expect(step.exitCode, isNull);
      expect(step.error, isNull);
      expect(step.errorCode, isNull);
      expect(step.createdAt, isNull);
      expect(step.inputTokens, isNull);
      expect(step.cacheReadTokens, isNull);
      expect(step.outputTokens, isNull);
      expect(step.content, '');
      expect(step.thinking, '');
      expect(step.toolCalls, isNull);
      expect(step.toolCallNames, isEmpty);
      expect(step.truncatedFields, isEmpty);
    });

    test('keeps unknown types, sources, and statuses', () {
      final step = TranscriptStep({
        'type': 'FUTURE_TYPE',
        'source': 'FUTURE_SOURCE',
        'status': 'FUTURE_STATUS',
      });

      expect(step.type.name, 'FUTURE_TYPE');
      expect(step.source.name, 'FUTURE_SOURCE');
      expect(step.status.name, 'FUTURE_STATUS');
      expect(switch (step.type) {
        StepType.plannerResponse => 'model call',
        StepType(:final name) => 'other: $name',
      }, 'other: FUTURE_TYPE');
    });

    test('is a tool result only for MODEL steps that are not messages or '
        'planner responses', () {
      bool isToolResult(String source, String type) =>
          TranscriptStep({'source': source, 'type': type}).isToolResult;

      expect(isToolResult('MODEL', 'GENERIC'), isTrue);
      expect(isToolResult('MODEL', 'RUN_COMMAND'), isTrue);
      expect(isToolResult('MODEL', 'SOME_FUTURE_TOOL'), isTrue);
      expect(isToolResult('MODEL', 'PLANNER_RESPONSE'), isFalse);
      expect(isToolResult('MODEL', 'EPHEMERAL_MESSAGE'), isFalse);
      expect(isToolResult('SYSTEM', 'SYSTEM_MESSAGE'), isFalse);
      expect(isToolResult('SYSTEM', 'ERROR_MESSAGE'), isFalse);
      expect(isToolResult('MODEL', 'ERROR_MESSAGE'), isFalse);
      expect(isToolResult('USER_EXPLICIT', 'USER_INPUT'), isFalse);
    });
  });

  group('pairToolResults', () {
    TranscriptStep calls(List<String> names) => TranscriptStep({
      'type': 'PLANNER_RESPONSE',
      'source': 'MODEL',
      'tool_calls': [
        for (final name in names) {'name': name},
      ],
    });
    TranscriptStep result(String content, {String type = 'GENERIC'}) =>
        TranscriptStep({'type': type, 'source': 'MODEL', 'content': content});
    TranscriptStep message(String type) =>
        TranscriptStep({'type': type, 'source': 'SYSTEM'});

    List<(String?, String)> pairs(List<TranscriptStep> steps) => [
      for (final (:toolName, :step) in pairToolResults(steps))
        (toolName, step.content),
    ];

    test('pairs results with calls in order', () {
      expect(
        pairs([
          calls(['read_file', 'run_command']),
          result('file'),
          message('SYSTEM_MESSAGE'),
          result('command', type: 'RUN_COMMAND'),
          result('extra'),
          calls(['search_web']),
          result('web'),
        ]),
        [
          ('read_file', 'file'),
          ('run_command', 'command'),
          ('search_web', 'web'),
        ],
      );
    });

    test('skips calls answered by an error message from any source', () {
      expect(
        pairs([
          calls(['bad_call', 'bad_call', 'run_command']),
          message('ERROR_MESSAGE'),
          result('', type: 'ERROR_MESSAGE'),
          result('command'),
        ]),
        [('run_command', 'command')],
      );
    });

    test('drops pending calls at the next planner response', () {
      expect(
        pairs([
          calls(['run_command']),
          TranscriptStep({'type': 'PLANNER_RESPONSE', 'source': 'MODEL'}),
          result('orphan'),
        ]),
        isEmpty,
      );
    });

    test('pairs malformed calls with a null tool name', () {
      expect(
        pairs([
          TranscriptStep({
            'type': 'PLANNER_RESPONSE',
            'source': 'MODEL',
            'tool_calls': ['malformed'],
          }),
          result('output'),
        ]),
        [(null, 'output')],
      );
    });
  });

  group('ConversationTranscript', () {
    test('cannot be modified', () {
      final transcript = ConversationTranscript(
        conversationId: 'conv',
        path: 'path',
        steps: [TranscriptStep({})],
        subagentIds: ['sub'],
        warnings: [const TranscriptWarning('conv', 'warning')],
      );

      expect(transcript.steps.clear, throwsUnsupportedError);
      expect(transcript.subagentIds.clear, throwsUnsupportedError);
      expect(transcript.warnings.clear, throwsUnsupportedError);
    });
  });

  group('ConversationTree', () {
    test('has the first transcript as its root and cannot be modified', () {
      final root = _transcript('root');
      final tree = ConversationTree(
        transcripts: [root, _transcript('sub')],
        warnings: [const TranscriptWarning('root', 'warning')],
      );

      expect(tree.root, same(root));
      expect(tree.transcripts.clear, throwsUnsupportedError);
      expect(tree.warnings.clear, throwsUnsupportedError);
    });
  });

  group('TranscriptWarning', () {
    test('describes the conversation, step, and problem', () {
      expect(
        const TranscriptWarning('conv', 'Broken.', stepIndex: 3).toString(),
        'conv (step 3): Broken.',
      );
      expect(
        const TranscriptWarning('conv', 'Broken.').toString(),
        'conv: Broken.',
      );
    });
  });

  group('TranscriptNotFoundException', () {
    test('lists each source and its locations', () {
      expect(
        TranscriptNotFoundException('conv', [
          _FakeSource('a'),
          _FakeSource('b', searchLocations: []),
        ]).toString(),
        'Transcript not found for conversation conv. Searched:\n'
        '  a: a-location\n'
        '  b: (nothing found)',
      );
    });

    test('says when there are no sources', () {
      expect(
        TranscriptNotFoundException('conv', []).toString(),
        'Transcript not found for conversation conv. Searched: '
        '(no transcript sources)',
      );
    });
  });

  group('resolveConversationId', () {
    test('returns the given ID, trimmed', () {
      expect(
        resolveConversationId(
          ' my-id ',
          sources: [_FakeSource('a', currentConversationId: 'env')],
        ),
        'my-id',
      );
    });

    test('falls back to the first detected current conversation', () {
      for (final id in [null, '   ']) {
        expect(
          resolveConversationId(
            id,
            sources: [
              _FakeSource('a'),
              _FakeSource('b', currentConversationId: 'b-id'),
            ],
          ),
          'b-id',
        );
      }
    });

    test('returns null when nothing is detected', () {
      expect(resolveConversationId(null, sources: [_FakeSource('a')]), isNull);
    });
  });

  group('loadTranscript', () {
    test('returns the transcript from the first source that has it', () async {
      final transcript = await loadTranscript(
        'conv',
        sources: [
          _FakeSource('a'),
          _FakeSource('b', transcripts: {'conv': []}),
          _FakeSource('c', transcripts: {'conv': []}),
        ],
      );

      expect(transcript?.path, 'b/conv');
    });

    test('returns null when no source has it', () async {
      expect(await loadTranscript('conv', sources: [_FakeSource('a')]), isNull);
    });
  });

  group('loadConversationTree', () {
    test('throws when the root transcript is missing', () async {
      final source = _FakeSource('a');

      await expectLater(
        loadConversationTree('missing', sources: [source]),
        throwsA(
          isA<TranscriptNotFoundException>()
              .having((e) => e.conversationId, 'conversationId', 'missing')
              .having((e) => e.sources, 'sources', [source]),
        ),
      );
    });

    test(
      'traverses breadth-first, handling cycles and shared subagents',
      () async {
        final tree = await loadConversationTree(
          'root',
          sources: [
            _FakeSource(
              'a',
              transcripts: {
                'root': ['sub-a', 'sub-b'],
                'sub-a': ['sub-c', 'root'],
                'sub-b': ['sub-c'],
                'sub-c': [],
              },
            ),
          ],
        );

        expect(tree.transcripts.map((t) => t.conversationId), [
          'root',
          'sub-a',
          'sub-b',
          'sub-c',
        ]);
        expect(tree.warnings, isEmpty);
      },
    );

    test('loads subagents from the same source as the root', () async {
      final tree = await loadConversationTree(
        'root',
        sources: [
          _FakeSource('a', transcripts: {'sub': []}),
          _FakeSource(
            'b',
            transcripts: {
              'root': ['sub'],
              'sub': [],
            },
          ),
        ],
      );

      expect(tree.transcripts.map((t) => t.path), ['b/root', 'b/sub']);
    });

    test('skips missing and unreadable subagents, with warnings', () async {
      final tree = await loadConversationTree(
        'root',
        sources: [
          _FakeSource(
            'a',
            transcripts: {
              'root': ['unreadable', 'sub'],
              'sub': ['missing'],
            },
            unreadable: {'unreadable'},
          ),
        ],
      );

      expect(tree.transcripts.map((t) => t.conversationId), ['root', 'sub']);
      expect(tree.warnings.map((w) => '$w'), [
        "root: Can't read the transcript of subagent unreadable: Unreadable",
        'sub: Subagent missing has no transcript.',
      ]);
    });

    test("includes each transcript's warnings first", () async {
      final tree = await loadConversationTree(
        'root',
        sources: [
          _FakeSource(
            'a',
            transcripts: {
              'root': ['sub', 'missing'],
              'sub': [],
            },
            warnings: {
              'root': ['Root warning.'],
              'sub': ['Sub warning.'],
            },
          ),
        ],
      );

      expect(tree.warnings.map((w) => '$w'), [
        'root: Root warning.',
        'sub: Sub warning.',
        'root: Subagent missing has no transcript.',
      ]);
    });
  });
}

/// A transcript for [conversationId] with no steps or subagents.
ConversationTranscript _transcript(String conversationId) =>
    ConversationTranscript(
      conversationId: conversationId,
      path: conversationId,
      steps: [],
      subagentIds: [],
    );

/// An in-memory [TranscriptSource] whose transcripts are described by a map
/// from conversation ID to subagent IDs.
final class _FakeSource extends TranscriptSource {
  @override
  final String name;

  @override
  final String? currentConversationId;

  @override
  final List<String> searchLocations;

  final Map<String, List<String>> transcripts;
  final Map<String, List<String>> warnings;
  final Set<String> unreadable;

  _FakeSource(
    this.name, {
    this.currentConversationId,
    List<String>? searchLocations,
    this.transcripts = const {},
    this.warnings = const {},
    this.unreadable = const {},
  }) : searchLocations = searchLocations ?? ['$name-location'];

  @override
  Future<ConversationTranscript?> loadTranscript(String conversationId) async {
    if (unreadable.contains(conversationId)) {
      throw FileSystemException('Unreadable', conversationId);
    }
    final subagentIds = transcripts[conversationId];
    if (subagentIds == null) return null;
    return ConversationTranscript(
      conversationId: conversationId,
      path: '$name/$conversationId',
      steps: [],
      subagentIds: subagentIds,
      warnings: [
        for (final message in warnings[conversationId] ?? const <String>[])
          TranscriptWarning(conversationId, message),
      ],
    );
  }
}
