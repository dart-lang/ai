// Copyright (c) 2026, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:skills/src/commands/get_command.dart';
import 'package:skills/src/commands/skills_command_runner.dart';
import 'package:skills/src/core/git_runner.dart';
import 'package:skills/src/agent/agent.dart';
import '../fake_dialog_support.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import '../utils.dart';

void main() {
  group(
    'Given a project with dependencies dep1 (2 skills) and dep2 (1 skill)',
    () {
      late String projectPath;
      late FakeDialogSupport fakeDialogSupport;

      setUpAll(() {
        Logger.root.onRecord.listen((r) => printOnFailure(r.toString()));
      });

      setUp(() async {
        final dep1Dir = d.dir('dep1', [
          pubspec('dep1'),
          d.dir('skills', [
            d.dir('dep1-skill1', [
              d.file('SKILL.md', '---\nname: dep1-skill1\n---\n'),
            ]),
          ]),
        ]);
        await dep1Dir.create();

        final projectRootDir = d.dir('project', [
          pubspec('project', dependencies: [.new('dep1')]),
        ]);
        await projectRootDir.create();

        projectPath = projectRootDir.io.path;
        fakeDialogSupport = FakeDialogSupport();
      });

      test('when running `skills get --all` without agent, user is prompted '
          'for agent and then all packages/skills are installed', () async {
        // Select 'generic' (index 0)
        fakeDialogSupport.multiSelectResults = [
          {0},
        ];

        final getCommand = GetCommand(
          dialogSupport: fakeDialogSupport,
          gitRunner: GitRunner(isAvailableOverride: () async => false),
        );
        final runner = SkillsCommandRunner('skills', 'Test')
          ..addCommand(getCommand);

        await runner.run(['get', '--directory', projectPath, '--all']);

        expect(fakeDialogSupport.allMultiSelectOptions, hasLength(1));
        expect(
          fakeDialogSupport.allMultiSelectOptions[0],
          unorderedEquals([
            'generic (antigravity, codex)',
            'claude',
            'cursor',
            'copilot',
            'cline',
            'opencode',
          ]),
        );
        expect(
          fakeDialogSupport.allTitles[0],
          equals('Unable to auto-detect agent. Please select one or more:'),
        );

        final skillsDir = Agent.generic.skillsPath(projectPath);
        final dep1Skill1Dir = Directory(p.join(skillsDir, 'dep1-skill1'));

        expect(await dep1Skill1Dir.exists(), isTrue);
      });
    },
  );
}
