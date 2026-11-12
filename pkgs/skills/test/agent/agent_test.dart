// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:skills/src/agent/agent.dart';
import 'package:test/test.dart';

void main() {
  group('Given a directory agent on a POSIX system', () {
    final context = p.Context(style: p.Style.posix, current: '/work');
    const projectPath = '/work/project';

    test(
      'when the directory is inside the project then it is stored relative',
      () {
        for (final directory in [
          'custom/dir',
          './custom/dir',
          '/work/project/custom/dir',
        ]) {
          final agent = Agent.directory(
            directory,
            projectPath: projectPath,
            context: context,
          );

          expect(agent.cliName, equals('dir:custom/dir'));
          expect(
            agent.skillsPath(projectPath, context: context),
            equals('/work/project/custom/dir'),
          );
        }
      },
    );

    test(
      'when the directory is outside the project then it is stored absolute',
      () {
        final agent = Agent.directory(
          '/outside/custom/dir',
          projectPath: projectPath,
          context: context,
        );

        expect(agent.cliName, equals('dir:/outside/custom/dir'));
        expect(
          agent.skillsPath(projectPath, context: context),
          equals('/outside/custom/dir'),
        );
      },
    );

    test(
      'when the directory is relative then it resolves against the project',
      () {
        // Resolved against the current directory (`/work`) instead,
        // `project/dir` would be inside the project and get stored as `dir`.
        final agent = Agent.directory(
          'project/dir',
          projectPath: projectPath,
          context: context,
        );

        expect(agent.cliName, equals('dir:project/dir'));
      },
    );

    test('when parsing its CLI name then returns the same agent', () {
      final agent = Agent.directory(
        'Custom/Dir',
        projectPath: projectPath,
        context: context,
      );

      final parsed = Agent.fromCliName(agent.cliName)!;

      expect(parsed.cliName, equals('dir:Custom/Dir'));
      expect(parsed.skillsRelativePath, equals(agent.skillsRelativePath));
    });

    test('when parsing a CLI name with no path then returns null', () {
      expect(Agent.fromCliName('dir:'), isNull);
      expect(Agent.fromCliName('dir: '), isNull);
    });

    test(
      'when its CLI name was written on Windows then it resolves to a POSIX path',
      () {
        final agent = Agent.fromCliName('dir:third_party/skills')!;

        expect(
          agent.skillsPath(projectPath, context: context),
          equals('/work/project/third_party/skills'),
        );
      },
    );
  });

  group('Given a directory agent on Windows', () {
    final context = p.Context(style: p.Style.windows, current: r'C:\work');
    const projectPath = r'C:\work\project';

    test(
      'when the directory is inside the project then it is stored relative with forward slashes',
      () {
        for (final directory in [
          r'third_party\skills',
          'third_party/skills',
          r'.\third_party\skills',
          r'C:\work\project\third_party\skills',
        ]) {
          final agent = Agent.directory(
            directory,
            projectPath: projectPath,
            context: context,
          );

          expect(agent.cliName, equals('dir:third_party/skills'));
          expect(
            agent.skillsPath(projectPath, context: context),
            equals(r'C:\work\project\third_party\skills'),
          );
        }
      },
    );

    test(
      'when the directory is outside the project then it is stored absolute with forward slashes',
      () {
        for (final (directory, cliName) in [
          (r'D:\other\skills', 'dir:D:/other/skills'),
          (r'\\server\share\skills', 'dir://server/share/skills'),
        ]) {
          final agent = Agent.directory(
            directory,
            projectPath: projectPath,
            context: context,
          );

          expect(agent.cliName, equals(cliName));
          expect(
            agent.skillsPath(projectPath, context: context),
            equals(directory),
          );
        }
      },
    );

    test(
      'when its CLI name was written on a POSIX system then it resolves to a Windows path',
      () {
        final agent = Agent.fromCliName('dir:third_party/skills')!;

        expect(
          agent.skillsPath(projectPath, context: context),
          equals(r'C:\work\project\third_party\skills'),
        );
      },
    );

    test('then a built-in agent resolves to a Windows path', () {
      expect(
        Agent.cursor.skillsPath(projectPath, context: context),
        equals(r'C:\work\project\.cursor\skills'),
      );
    });
  });
}
