// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:manual_evals/manual_evals.dart';
import 'package:test/test.dart';

void main() {
  group('checkTranscriptFormat', () {
    List<String> problemsOf(
      List<List<Map<String, Object?>>> transcripts, {
      List<TranscriptWarning> warnings = const [],
    }) {
      final tree = ConversationTree(
        transcripts: [
          for (final (index, steps) in transcripts.indexed)
            ConversationTranscript(
              conversationId: 'conv-$index',
              path: 'conv-$index',
              steps: [
                for (final (stepIndex, step) in steps.indexed)
                  TranscriptStep({'step_index': stepIndex, ...step}),
              ],
              subagentIds: [],
            ),
        ],
        warnings: warnings,
      );
      return [for (final problem in checkTranscriptFormat(tree)) '$problem'];
    }

    test('finds no problems in a well-formed tree', () {
      expect(
        problemsOf([
          [
            {'type': 'USER_INPUT', 'source': 'USER_EXPLICIT'},
            _modelCall(['read_file', 'run_command']),
            _result(),
            {'type': 'SYSTEM_MESSAGE', 'source': 'SYSTEM'},
            _result(type: 'RUN_COMMAND'),
            _modelCall(['bad_call']),
            {'type': 'ERROR_MESSAGE', 'source': 'SYSTEM'},
            _modelCall(['run_command']),
          ],
          [_modelCall([], tokens: false)],
        ]),
        isEmpty,
      );
    });

    test("includes the tree's warnings first", () {
      expect(
        problemsOf(
          [
            [_modelCall([])],
          ],
          warnings: [const TranscriptWarning('conv-0', 'Warning.')],
        ),
        ['conv-0: Warning.'],
      );
    });

    test('reports transcripts without model calls', () {
      expect(
        problemsOf([
          [_modelCall([])],
          [
            {'type': 'USER_INPUT', 'source': 'USER_EXPLICIT'},
          ],
          [],
        ]),
        ['conv-1: No PLANNER_RESPONSE steps.'],
      );
    });

    test('reports model calls with missing or extra tool results', () {
      expect(
        problemsOf([
          [
            _modelCall(['read_file', 'run_command']),
            _result(),
            _modelCall(['read_file']),
            _result(),
            _result(),
            _modelCall(['read_file', 'run_command']),
            _result(),
          ],
        ]),
        [
          'conv-0 (step 0): Found 1 tool result for 2 tool calls.',
          'conv-0 (step 2): Found 2 tool results for 1 tool call.',
        ],
      );
    });

    test('does not count error messages as extra tool results', () {
      expect(
        problemsOf([
          [
            _modelCall(['run_command']),
            _result(),
            _result(type: 'ERROR_MESSAGE'),
          ],
        ]),
        isEmpty,
      );
    });

    test('reports extra tool results for the last model call', () {
      expect(
        problemsOf([
          [_modelCall([]), _result()],
        ]),
        ['conv-0 (step 0): Found 1 tool result for 0 tool calls.'],
      );
    });

    test('reports a tree in which no model call recorded token usage', () {
      expect(
        problemsOf([
          [_modelCall([], tokens: false)],
          [_modelCall([], tokens: false)],
        ]),
        [
          'conv-0: No model call in the conversation or its subagents '
              'recorded token usage.',
        ],
      );
    });
  });
}

/// A `PLANNER_RESPONSE` step that calls the tools named [toolNames], with
/// token usage if [tokens] is true.
Map<String, Object?> _modelCall(List<String> toolNames, {bool tokens = true}) =>
    {
      'type': 'PLANNER_RESPONSE',
      'source': 'MODEL',
      if (tokens) ...{'input_tokens': 10, 'output_tokens': 5},
      'tool_calls': [
        for (final name in toolNames) {'name': name},
      ],
    };

/// A tool result step of [type].
Map<String, Object?> _result({String type = 'GENERIC'}) => {
  'type': type,
  'source': 'MODEL',
};
