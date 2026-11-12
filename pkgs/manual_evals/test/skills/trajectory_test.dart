// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:manual_evals/manual_evals.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  /// Runs the script with transcripts read from the sandbox.
  Future<ProcessResult> run(List<String> args) => Process.run(
    Platform.resolvedExecutable,
    ['skills/manual-evals-trajectory/scripts/trajectory.dart', ...args],
    environment: {
      AntigravityTranscriptSource.rootsEnvironmentVariable: d.sandbox,
      Platform.isWindows ? 'USERPROFILE' : 'HOME': d.sandbox,
    },
    // The report is UTF-8, which isn't the system encoding on Windows.
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );

  test('prints a report', () async {
    await d.dir('conv', [
      d.dir('.system_generated', [
        d.dir('logs', [
          d.file(
            'transcript_full.jsonl',
            [
              {
                'step_index': 0,
                'type': 'PLANNER_RESPONSE',
                'source': 'MODEL',
                'tool_calls': [
                  {
                    'name': 'run_command',
                    'args': {'CommandLine': 'ls ${d.sandbox}/x'},
                  },
                ],
              },
              {
                'step_index': 1,
                'type': 'GENERIC',
                'source': 'MODEL',
                'status': 'DONE',
                'content': 'Command exited with code 0.',
              },
            ].map(jsonEncode).join('\n'),
          ),
        ]),
      ]),
    ]).create();

    final result = await run(['conv']);

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(result.stdout, startsWith('# Trajectory\n'));
    expect(result.stdout, contains('- ✅ `run_command` `ls ~/x`\n'));
    expect(result.stdout, contains('| run_command | 1 | 0 | 100.0% |'));
  });

  test('prints usage for --help', () async {
    final result = await run(['--help']);

    expect(result.exitCode, 0);
    expect(result.stdout, contains('Usage:'));
  });

  test('fails cleanly when the transcript is missing', () async {
    final result = await run(['missing']);

    expect(result.exitCode, 1);
    expect(result.stderr, contains('Transcript not found'));
  });

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
