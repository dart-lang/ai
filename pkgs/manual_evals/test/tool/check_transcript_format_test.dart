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
  /// Runs the tool with transcripts read from the sandbox.
  Future<ProcessResult> run(List<String> args) => Process.run(
    Platform.resolvedExecutable,
    ['tool/check_transcript_format.dart', ...args],
    environment: {
      AntigravityTranscriptSource.rootsEnvironmentVariable: d.sandbox,
    },
  );

  /// Writes a transcript for [conversationId] containing [steps].
  Future<void> writeTranscript(
    String conversationId,
    List<Map<String, Object?>> steps,
  ) =>
      d.dir(conversationId, [
        d.dir('.system_generated', [
          d.dir('logs', [
            d.file('transcript_full.jsonl', steps.map(jsonEncode).join('\n')),
          ]),
        ]),
      ]).create();

  Map<String, Object?> modelCall(int index, List<String> toolNames) => {
    'step_index': index,
    'type': 'PLANNER_RESPONSE',
    'source': 'MODEL',
    'input_tokens': 10,
    'output_tokens': 5,
    'tool_calls': [
      for (final name in toolNames) {'name': name},
    ],
  };

  test('reports OK for a well-formed transcript', () async {
    await writeTranscript('conv', [modelCall(0, [])]);

    final result = await run(['conv']);

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(result.stdout, contains('OK: all transcripts were understood.'));
  });

  test('lists at most 20 problems unless --all is given', () async {
    await writeTranscript('conv', [
      for (var i = 0; i < 25; i++) modelCall(i, ['run_command']),
    ]);

    final limited = await run(['conv']);
    final all = await run(['--all', 'conv']);

    expect(limited.exitCode, 1);
    expect(limited.stdout, contains('24 problems found:'));
    expect(limited.stdout, contains('...and 4 more. Use --all to see them.'));
    expect(all.exitCode, 1);
    expect(all.stdout, isNot(contains('more.')));
    expect(
      LineSplitter.split(all.stdout as String).where((l) => l.startsWith('- ')),
      hasLength(24),
    );
  });

  test('fails cleanly when the transcript is missing', () async {
    final result = await run(['missing']);

    expect(result.exitCode, 1);
    expect(result.stderr, contains('Transcript not found'));
  });

  test('fails cleanly when the transcript cannot be read', () async {
    await writeTranscript('conv', [modelCall(0, [])]);
    final file = p.join(
      d.sandbox,
      'conv',
      '.system_generated',
      'logs',
      'transcript_full.jsonl',
    );
    Process.runSync('chmod', ['000', file]);

    final result = await run(['conv']);

    expect(result.exitCode, 1);
    expect(result.stderr, contains("Can't read the transcript of conv"));
    expect(result.stderr, isNot(contains('Unhandled exception')));
  }, skip: Platform.isWindows ? 'Uses chmod' : false);

  test('rejects unknown arguments', () async {
    for (final args in [
      ['--verbose'],
      ['a', 'b'],
    ]) {
      final result = await run(args);

      expect(result.exitCode, 64, reason: '$args');
      expect(result.stderr, contains('Usage:'), reason: '$args');
    }
  });
}
