// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:manual_evals/manual_evals.dart';
import 'package:test/test.dart';

import 'steps.dart';

void main() {
  group('TokenCounts', () {
    test('adds counts and totals them', () {
      const a = TokenCounts(input: 1, cacheRead: 2, output: 3);
      const b = TokenCounts(input: 10, cacheRead: 20, output: 30);
      final sum = a + b;

      expect(sum.input, 11);
      expect(sum.cacheRead, 22);
      expect(sum.output, 33);
      expect(sum.total, 66);
      expect(TokenCounts.zero.total, 0);
    });
  });

  group('measureTokenUsage', () {
    test('sums recorded tokens per turn and in total', () {
      final usage = measureTokenUsage(
        transcript([
          userInput('First'),
          modelCall(input: 1, cacheRead: 10, output: 100),
          modelCall(input: 2, cacheRead: 20, output: 200),
          userInput('Second'),
          modelCall(input: 3, cacheRead: 30, output: 300),
        ]),
      );

      expect(usage.conversationId, 'conv');
      expect(_turns(usage), [
        ('First', 2, 3, 30, 300),
        ('Second', 1, 3, 30, 300),
      ]);
      expect(usage.modelCalls, 3);
      expect(usage.tokens.total, 666);
      expect(usage.unrecordedModelCalls, 0);
    });

    test('puts model calls before the first request in their own turn', () {
      final usage = measureTokenUsage(
        transcript([
          systemMessage('Prompt'),
          modelCall(input: 1),
          userInput('Later'),
        ]),
      );

      expect(_turns(usage), [(null, 1, 1, 0, 0), ('Later', 0, 0, 0, 0)]);
    });

    test('has no turns when there are no requests or model calls', () {
      expect(measureTokenUsage(transcript([])).turns, isEmpty);
    });

    test('counts model calls that recorded no usage', () {
      final usage = measureTokenUsage(
        transcript([
          userInput('Request'),
          modelCall(),
          modelCall(cacheRead: 5),
        ]),
      );

      expect(usage.modelCalls, 2);
      expect(usage.unrecordedModelCalls, 1);
      expect(usage.tokens.total, 5);
    });

    test('keeps the whole request on one line', () {
      String request(String content) => measureTokenUsage(
        transcript([
          {'type': 'USER_INPUT', 'source': 'USER_EXPLICIT', 'content': content},
        ]),
      ).turns.single.request!;

      expect(
        request(
          '<USER_REQUEST>\n  Hello\n\n world  \n</USER_REQUEST>\n'
          '<ADDITIONAL_METADATA>\nThe user is: someone.\n'
          '</ADDITIONAL_METADATA>',
        ),
        'Hello world',
      );
      expect(
        request(
          'The user left comments.\n<USER_REQUEST>\n</USER_REQUEST>\n'
          '<ADDITIONAL_METADATA>\nThe user is: someone.\n'
          '</ADDITIONAL_METADATA>',
        ),
        'The user left comments.',
      );
      expect(request('No tags'), 'No tags');
      expect(request('word ' * 50), ('word ' * 50).trim());
    });

    test('counts calls and result characters per tool', () {
      final usage = measureTokenUsage(
        transcript([
          userInput('Request'),
          modelCall(tools: ['read_file', 'run_command', 'read_file']),
          toolResult('12345'),
          toolResult('1234567890'),
          toolResult('123'),
          modelCall(tools: ['bad_call', 'grep']),
          {'type': 'ERROR_MESSAGE', 'source': 'SYSTEM'},
          toolResult('1'),
          {
            'type': 'PLANNER_RESPONSE',
            'source': 'MODEL',
            'tool_calls': ['malformed'],
          },
          toolResult('12'),
          modelCall(tools: ['run_command']),
        ]),
      );

      expect(
        [
          for (final MapEntry(key: name, value: tool) in usage.tools.entries)
            (name, tool.calls, tool.resultCharacters),
        ],
        [
          ('read_file', 2, 8),
          ('run_command', 2, 10),
          ('bad_call', 1, 0),
          ('grep', 1, 1),
          ('(unknown)', 1, 2),
        ],
      );
    });
  });
}

/// The request, model calls, and token counts of each of [usage]'s turns.
List<(String?, int, int, int, int)> _turns(ConversationUsage usage) => [
  for (final turn in usage.turns)
    (
      turn.request,
      turn.modelCalls,
      turn.tokens.input,
      turn.tokens.cacheRead,
      turn.tokens.output,
    ),
];
