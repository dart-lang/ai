import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:skills/src/commands/get_command.dart';
import 'package:skills/src/commands/skills_command_runner.dart';
import 'package:skills/src/core/git_runner.dart';
import 'package:skills/src/agent/adapters/agent_skills_adapter.dart';
import 'package:skills/src/agent/adapters/generic_adapter.dart';
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
      late AgentSkillsAdapter skillsAdapter;

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
            d.dir('dep1-skill2', [
              d.file('SKILL.md', '---\nname: dep1-skill2\n---\n'),
            ]),
          ]),
        ]);
        await dep1Dir.create();

        final dep2Dir = d.dir('dep2', [
          pubspec('dep2'),
          d.dir('skills', [
            d.dir('dep2-skill1', [
              d.file('SKILL.md', '---\nname: dep2-skill1\n---\n'),
            ]),
          ]),
        ]);
        await dep2Dir.create();

        final projectRootDir = d.dir('project', [
          pubspec('project', dependencies: [.new('dep1'), .new('dep2')]),
          d.dir('.cursor', [d.dir('skills')]),
        ]);
        await projectRootDir.create();

        projectPath = projectRootDir.io.path;
        fakeDialogSupport = FakeDialogSupport();
        skillsAdapter = GenericAdapter(
          projectPath,
          dialogSupport: fakeDialogSupport,
        );
      });

      test('when running `skills get dep1` (interactive) and user selects only '
          'dep1-skill1, then only dep1-skill1 should be installed', () async {
        fakeDialogSupport.multiSelectResults.add({0});

        final getCommand = GetCommand(
          dialogSupport: fakeDialogSupport,
          gitRunner: GitRunner(isAvailableOverride: () async => false),
        );
        final runner = SkillsCommandRunner('skills', 'Test')
          ..addCommand(getCommand);

        await runner.run([
          'get',
          '--directory',
          projectPath,
          '--agent',
          Agent.generic.cliName,
          '--package',
          'dep1',
        ]);

        expect(fakeDialogSupport.allMultiSelectOptions, hasLength(1));
        expect(
          fakeDialogSupport.allMultiSelectOptions[0],
          unorderedEquals([contains('dep1-skill1'), contains('dep1-skill2')]),
        );
        expect(fakeDialogSupport.allInitialSelected[0], isEmpty);
        expect(
          fakeDialogSupport.allTitles[0],
          equals('Select skills to install/update from package:dep1:'),
        );

        final dep1Skill1Dir = Directory(
          p.join(skillsAdapter.skillsDirectory, 'dep1-skill1'),
        );
        final dep1Skill2Dir = Directory(
          p.join(skillsAdapter.skillsDirectory, 'dep1-skill2'),
        );

        expect(await dep1Skill1Dir.exists(), isTrue);
        expect(await dep1Skill2Dir.exists(), isFalse);
      });

      test(
        'when running `skills get` (interactive), user selects both packages, '
        'then selects only dep1-skill1 from dep1, then dep1-skill1 and '
        'dep2-skill1 should be installed',
        () async {
          fakeDialogSupport.multiSelectResults = [
            {0, 1}, // Select both packages
            {0}, // Select dep1-skill1 from dep1 skills
            {0}, // Select dep2-skill1 from dep2 skills
          ];

          final getCommand = GetCommand(
            dialogSupport: fakeDialogSupport,
            gitRunner: GitRunner(isAvailableOverride: () async => false),
          );
          final runner = SkillsCommandRunner('skills', 'Test')
            ..addCommand(getCommand);

          await runner.run([
            'get',
            '--directory',
            projectPath,
            '--agent',
            Agent.generic.cliName,
          ]);

          expect(fakeDialogSupport.allMultiSelectOptions, hasLength(3));
          expect(
            fakeDialogSupport.allMultiSelectOptions[0],
            unorderedEquals(['package:dep1', 'package:dep2']),
          );
          expect(
            fakeDialogSupport.allMultiSelectOptions[1],
            unorderedEquals([
              contains('dep1-skill1 (New)'),
              contains('dep1-skill2 (New)'),
            ]),
          );
          expect(
            fakeDialogSupport.allTitles[1],
            equals('Select skills to install/update from package:dep1:'),
          );

          final dep1Skill1Dir = Directory(
            p.join(skillsAdapter.skillsDirectory, 'dep1-skill1'),
          );
          final dep1Skill2Dir = Directory(
            p.join(skillsAdapter.skillsDirectory, 'dep1-skill2'),
          );
          final dep2Skill1Dir = Directory(
            p.join(skillsAdapter.skillsDirectory, 'dep2-skill1'),
          );

          expect(await dep1Skill1Dir.exists(), isTrue);
          expect(await dep1Skill2Dir.exists(), isFalse);
          expect(await dep2Skill1Dir.exists(), isTrue);
        },
      );
    },
  );

  group(
    'Given a project with dependencies dep1 (2 skills) and dep2 (2 skills)',
    () {
      late String projectPath;
      late FakeDialogSupport fakeDialogSupport;
      late AgentSkillsAdapter skillsAdapter;

      setUp(() async {
        final dep1Dir = d.dir('dep1', [
          pubspec('dep1'),
          d.dir('skills', [
            d.dir('dep1-skill1', [
              d.file('SKILL.md', '---\nname: dep1-skill1\n---\n'),
            ]),
            d.dir('dep1-skill2', [
              d.file('SKILL.md', '---\nname: dep1-skill2\n---\n'),
            ]),
          ]),
        ]);
        await dep1Dir.create();

        final dep2Dir = d.dir('dep2', [
          pubspec('dep2'),
          d.dir('skills', [
            d.dir('dep2-skill1', [
              d.file('SKILL.md', '---\nname: dep2-skill1\n---\n'),
            ]),
            d.dir('dep2-skill2', [
              d.file('SKILL.md', '---\nname: dep2-skill2\n---\n'),
            ]),
          ]),
        ]);
        await dep2Dir.create();

        final projectRootDir = d.dir('project', [
          pubspec('project', dependencies: [.new('dep1'), .new('dep2')]),
          d.dir('.cursor', [d.dir('skills')]),
        ]);
        await projectRootDir.create();

        projectPath = projectRootDir.io.path;
        fakeDialogSupport = FakeDialogSupport();
        skillsAdapter = GenericAdapter(
          projectPath,
          dialogSupport: fakeDialogSupport,
        );
      });

      test('when running `skills get` (interactive), user selects both packages, '
          'then selects only dep1-skill1 from dep1 and dep2-skill2 from dep2, '
          'then only those should be installed', () async {
        fakeDialogSupport.multiSelectResults = [
          {0, 1}, // Select both packages
          {
            0,
          }, // Select dep1-skill1 from dep1 (options: dep1-skill1, dep1-skill2)
          {
            1,
          }, // Select dep2-skill2 from dep2 (options: dep2-skill1, dep2-skill2)
        ];

        final getCommand = GetCommand(
          dialogSupport: fakeDialogSupport,
          gitRunner: GitRunner(isAvailableOverride: () async => false),
        );
        final runner = SkillsCommandRunner('skills', 'Test')
          ..addCommand(getCommand);

        await runner.run([
          'get',
          '--directory',
          projectPath,
          '--agent',
          Agent.generic.cliName,
        ]);

        expect(fakeDialogSupport.allMultiSelectOptions, hasLength(3));
        expect(
          fakeDialogSupport.allMultiSelectOptions[0],
          unorderedEquals(['package:dep1', 'package:dep2']),
        );
        expect(
          fakeDialogSupport.allMultiSelectOptions[1],
          unorderedEquals([
            contains('dep1-skill1 (New)'),
            contains('dep1-skill2 (New)'),
          ]),
        );
        expect(
          fakeDialogSupport.allMultiSelectOptions[2],
          unorderedEquals([
            contains('dep2-skill1 (New)'),
            contains('dep2-skill2 (New)'),
          ]),
        );

        // Sorted by display name: package dep1, package dep2
        expect(
          fakeDialogSupport.allTitles[1],
          equals('Select skills to install/update from package:dep1:'),
        );
        expect(
          fakeDialogSupport.allTitles[2],
          equals('Select skills to install/update from package:dep2:'),
        );

        final dep1Skill1Dir = Directory(
          p.join(skillsAdapter.skillsDirectory, 'dep1-skill1'),
        );
        final dep1Skill2Dir = Directory(
          p.join(skillsAdapter.skillsDirectory, 'dep1-skill2'),
        );
        final dep2Skill1Dir = Directory(
          p.join(skillsAdapter.skillsDirectory, 'dep2-skill1'),
        );
        final dep2Skill2Dir = Directory(
          p.join(skillsAdapter.skillsDirectory, 'dep2-skill2'),
        );

        expect(await dep1Skill1Dir.exists(), isTrue);
        expect(await dep1Skill2Dir.exists(), isFalse);
        expect(await dep2Skill1Dir.exists(), isFalse);
        expect(await dep2Skill2Dir.exists(), isTrue);
      });
    },
  );
}
