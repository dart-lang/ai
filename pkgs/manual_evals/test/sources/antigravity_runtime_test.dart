// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:manual_evals/src/sources/antigravity_runtime.dart';
import 'package:test/test.dart';

void main() {
  test(
    'backgroundTaskId reads the task of a call running in the background',
    () {
      expect(
        backgroundTaskId(
          'Created At: 2026-01-01T00:00:00Z\n'
          'Tool is running as a background task with task id: conv/task-7\n'
          'Log output:\n',
        ),
        'conv/task-7',
      );
      expect(backgroundTaskId('Command exited with code 0.'), isNull);
    },
  );

  test('reportedExitCode reads only the header', () {
    expect(reportedExitCode('Command exited with code 2.'), 2);
    expect(reportedExitCode('The command exited with code -1.'), -1);
    expect(
      reportedExitCode('Command output:\nCommand exited with code 1.'),
      isNull,
    );
    expect(reportedExitCode('no code'), isNull);
  });

  test('toolOutput strips the header', () {
    expect(
      toolOutput(
        'Created At: 2026-01-01T00:00:00Z\n'
        'Command exited with code 1.\n'
        '\n'
        'Command output:\n'
        'out\n',
      ),
      'out',
    );
    expect(
      toolOutput(
        'Created At: 2026-01-01T00:00:00Z\n'
        'Completed At: 2026-01-01T00:00:01Z\n'
        'Command exited with code 1.\n'
        'out',
      ),
      'out',
    );
    expect(toolOutput('  plain  '), 'plain');
  });

  group('runtime messages', () {
    const content =
        'The following is a <SYSTEM_MESSAGE> not actually sent by the user.\n'
        '\n'
        '<SYSTEM_MESSAGE>\n'
        '[Message] timestamp=2026-01-01T00:00:00Z sender=conv/task-1 '
        'priority=MESSAGE_PRIORITY_HIGH content=Task id "conv/task-1" '
        'finished with result:\n'
        'Command exited with code 0.\n'
        'Log: file:///logs/task-1.log\n'
        '[Message] timestamp=2026-01-01T00:00:01Z sender=parent '
        'priority=MESSAGE_PRIORITY_HIGH content=Keep going.\n'
        '</SYSTEM_MESSAGE>';

    test('are split by sender', () {
      expect(
        [for (final (:sender, text: _) in runtimeMessages(content)) sender],
        ['conv/task-1', 'parent'],
      );
      expect(runtimeMessages('No messages.'), isEmpty);
    });

    test('have content without the trailer', () {
      expect(
        [
          for (final (sender: _, :text) in runtimeMessages(content))
            messageContent(text),
        ],
        [
          'Task id "conv/task-1" finished with result:\n'
              'Command exited with code 0.',
          'Keep going.',
        ],
      );
      expect(messageContent('timestamp=x sender=y'), isNull);
    });

    test('report the results of background tasks', () {
      TaskResult? result(String how) => taskResult(
        'timestamp=x sender=t content=Task id "t" $how with result:\n'
        'output\n'
        'Log: file:///t.log\n'
        '</SYSTEM_MESSAGE>',
      );

      expect(result('finished'), (end: TaskEnd.finished, result: 'output'));
      expect(result('failed'), (end: TaskEnd.failed, result: 'output'));
      expect(result('was canceled'), (end: TaskEnd.canceled, result: 'output'));
      expect(taskResult('timestamp=x sender=t content=Hello'), isNull);
    });
  });
}
