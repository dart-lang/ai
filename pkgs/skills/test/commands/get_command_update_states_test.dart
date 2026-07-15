import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:skills/src/commands/get_command.dart';
import 'package:skills/src/commands/skills_command_runner.dart';
import 'package:skills/src/core/git_runner.dart';
import 'package:skills/src/agent/agent.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import '../fake_dialog_support.dart';
import '../utils.dart';

void main() {
  setUpAll(() {
    Logger.root.onRecord.listen((r) => printOnFailure(r.toString()));
  });

  group('Given a project with an installed skill', () {
    late String projectPath;
    late FakeDialogSupport fakeDialogSupport;
    late d.DirectoryDescriptor depDir;
    const defaultSkillContent =
        '---\nname: dep-skill1\n---\nOriginal content\n';

    setUp(() async {
      depDir = d.dir('dep', [
        pubspec('dep'),
        d.dir('skills', [
          d.dir('dep-skill1', [d.file('SKILL.md', defaultSkillContent)]),
        ]),
      ]);
      await depDir.create();

      final projectRootDir = d.dir('project', [
        pubspec('test_app', dependencies: [.new('dep')]),
        d.dir('.agents', [d.dir('skills')]),
      ]);
      await projectRootDir.create();

      projectPath = projectRootDir.io.path;
      fakeDialogSupport = FakeDialogSupport();
    });

    Future<void> runGetCommand({bool all = false}) async {
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
        'dep',
        if (all) '--all',
      ]);
    }

    Future<void> expectSkill({
      bool isInstalled = true,
      String content = defaultSkillContent,
      String skill = 'dep-skill1',
    }) async {
      await d.dir('project', [
        d.dir('.agents', [
          d.dir('skills', [
            isInstalled
                ? d.dir(skill, [d.file('SKILL.md', content)])
                : d.nothing(skill),
          ]),
        ]),
      ]).validate();
    }

    test('when running skills get again with no changes', () async {
      await runGetCommand(all: true);
      await expectSkill();

      fakeDialogSupport.reset();
      fakeDialogSupport.allInitialSelected.clear();

      await runGetCommand();
      expect(
        fakeDialogSupport.allMultiSelectOptions,
        isEmpty,
        reason: 'then no prompt is shown',
      );
    });

    test(
      'when running skills get after the source skill is modified',
      () async {
        await runGetCommand(all: true);
        await expectSkill();

        // Modify source skill
        final skillFile = File(
          p.join(depDir.io.path, 'skills', 'dep-skill1', 'SKILL.md'),
        );
        await skillFile.writeAsString(
          '---\nname: dep-skill1\n---\nUpdated content\n',
        );

        // Run again
        fakeDialogSupport.multiSelectResults.add({0});
        await runGetCommand();

        expect(fakeDialogSupport.allMultiSelectOptions, hasLength(1));
        expect(fakeDialogSupport.allMultiSelectOptions[0], [
          contains('dep-skill1 (Update available)'),
        ], reason: 'then the prompt shows the Update available state');
        expect(
          fakeDialogSupport.allInitialSelected[0],
          contains(0),
          reason: 'then it is selected by default',
        );
      },
    );

    test(
      'when running skills get after the installed skill is modified locally',
      () async {
        await runGetCommand(all: true);
        await expectSkill();

        // Modify installed skill locally
        final installedSkillFile = File(
          p.join(projectPath, '.agents', 'skills', 'dep-skill1', 'SKILL.md'),
        );
        final editedContent = '---\nname: dep-skill1\n---\nLocal edits\n';
        await installedSkillFile.writeAsString(editedContent);

        fakeDialogSupport.multiSelectResults.add({0});
        await runGetCommand();
        await expectSkill(content: defaultSkillContent);

        expect(fakeDialogSupport.allMultiSelectOptions, hasLength(1));
        expect(fakeDialogSupport.allMultiSelectOptions[0], [
          contains('dep-skill1 (Local edits)'),
        ], reason: 'then the prompt shows the Local edits state');
        expect(
          fakeDialogSupport.allInitialSelected[0],
          isEmpty,
          reason: 'then it is not selected by default',
        );
      },
    );

    test(
      'when running skills get after previously skipping the skill',
      () async {
        // First install, don't select any
        fakeDialogSupport.multiSelectResults.add({});
        await runGetCommand();
        await expectSkill(isInstalled: false);
        fakeDialogSupport.reset();

        // Install again, but select the previously skipped one.
        fakeDialogSupport.multiSelectResults.add({0});
        await runGetCommand();

        expect(fakeDialogSupport.allMultiSelectOptions, hasLength(1));
        expect(fakeDialogSupport.allMultiSelectOptions[0], [
          contains('dep-skill1 (Skipped previously)'),
        ], reason: 'then the prompt shows the Skipped previously state');
        expect(
          fakeDialogSupport.allInitialSelected[0],
          isEmpty,
          reason: 'then it is not selected by default',
        );

        await expectSkill();
      },
    );

    test('when running skills get after the source skill is deleted', () async {
      await runGetCommand(all: true);

      // Delete source skill
      final sourceSkillDir = Directory(
        p.join(depDir.io.path, 'skills', 'dep-skill1'),
      );
      await sourceSkillDir.delete(recursive: true);

      // Run again
      fakeDialogSupport.multiSelectResults.add({0});
      await runGetCommand();

      expect(fakeDialogSupport.allMultiSelectOptions, hasLength(1));
      expect(fakeDialogSupport.allMultiSelectOptions[0], [
        contains('dep-skill1 (Removed)'),
      ], reason: 'then the prompt shows the Removed state');
      expect(
        fakeDialogSupport.allInitialSelected[0],
        contains(0),
        reason: 'then it is selected by default to remove',
      );

      await expectSkill(isInstalled: false);
    });

    test(
      'when running skills get after a new skill is added to the source',
      () async {
        await runGetCommand(all: true);

        // Add a new skill
        final newSkillDir = Directory(
          p.join(depDir.io.path, 'skills', 'dep-skill2'),
        );
        await newSkillDir.create(recursive: true);
        final newSkillContent = '---\nname: dep-skill2\n---\nNew\n';
        await File(
          p.join(newSkillDir.path, 'SKILL.md'),
        ).writeAsString(newSkillContent);

        // Run again and select the new skill
        fakeDialogSupport.multiSelectResults.add({0});
        await runGetCommand();
        await expectSkill(skill: 'dep-skill2', content: newSkillContent);

        expect(fakeDialogSupport.allMultiSelectOptions, hasLength(1));

        expect(fakeDialogSupport.allMultiSelectOptions[0], [
          contains('dep-skill2 (New)'),
        ], reason: 'then the prompt shows only the skill with the New state');

        expect(
          fakeDialogSupport.allInitialSelected[0],
          isEmpty,
          reason: 'then it is not selected by default',
        );
      },
    );
    test(
      'when running skills get with --all it applies all changes without prompting',
      () async {
        // Set up the base state with two skills
        final skill2Dir = Directory(
          p.join(depDir.io.path, 'skills', 'dep-skill2'),
        );
        await skill2Dir.create(recursive: true);
        await File(
          p.join(skill2Dir.path, 'SKILL.md'),
        ).writeAsString('---\nname: dep-skill2\n---\n');

        await runGetCommand(all: true);
        await expectSkill(skill: 'dep-skill1');
        await expectSkill(
          skill: 'dep-skill2',
          content: '---\nname: dep-skill2\n---\n',
        );

        // 1. Delete dep-skill1 (Removed)
        await Directory(
          p.join(depDir.io.path, 'skills', 'dep-skill1'),
        ).delete(recursive: true);

        // 2. Modify dep-skill2 (Update available)
        final editedContent = '---\nname: dep-skill2\n---\nUpdated\n';
        await File(
          p.join(skill2Dir.path, 'SKILL.md'),
        ).writeAsString(editedContent);

        // 3. Add dep-skill3 (New)
        final skill3Dir = Directory(
          p.join(depDir.io.path, 'skills', 'dep-skill3'),
        );
        await skill3Dir.create(recursive: true);
        final newSkillContent = '---\nname: dep-skill3\n---\n';
        await File(
          p.join(skill3Dir.path, 'SKILL.md'),
        ).writeAsString(newSkillContent);

        fakeDialogSupport.reset();
        await runGetCommand(all: true);

        expect(
          fakeDialogSupport.allMultiSelectOptions,
          isEmpty,
          reason: 'then should not show any prompts',
        );

        await expectSkill(skill: 'dep-skill1', isInstalled: false);
        await expectSkill(skill: 'dep-skill2', content: editedContent);
        await expectSkill(skill: 'dep-skill3', content: newSkillContent);
      },
    );
  });
}
