import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:skills/src/commands/get_command.dart';
import 'package:skills/src/commands/skills_command_runner.dart';
import 'package:skills/src/core/git_runner.dart';
import 'package:skills/src/ide/adapters/agent_skills_adapter.dart';
import 'package:skills/src/ide/adapters/generic_adapter.dart';
import 'package:skills/src/ide/ide.dart';
import 'package:skills/src/models/skill_manifest.dart';
import '../fake_dialog_support.dart';
import '../utils.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  group('Given a project with dependencies dep1 and dep2 having skills', () {
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
          d.dir('dep1-skill', [
            d.file('SKILL.md', '---\nname: dep1-skill\n---\n'),
          ]),
        ]),
      ]);
      await dep1Dir.create();

      final dep2Dir = d.dir('dep2', [
        pubspec('dep2'),
        d.dir('skills', [
          d.dir('dep2-skill', [
            d.file('SKILL.md', '---\nname: dep2-skill\n---\n'),
          ]),
        ]),
      ]);
      await dep2Dir.create();

      final dep3Dir = d.dir('dep3', [pubspec('dep3')]);
      await dep3Dir.create();

      final projectRootDir = d.dir('project', [
        pubspec(
          'test_app',
          dependencies: [.new('dep1'), .new('dep2'), .new('dep3')],
        ),
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

    test('when running `skills get` and the user only selects dep1 then only '
        'dep1 should be installed', () async {
      fakeDialogSupport.multiSelectResults.addAll([
        {0},
        {0},
      ]);
      final getCommand = GetCommand(
        dialogSupport: fakeDialogSupport,
        gitRunner: GitRunner(
          isAvailableOverride: () async => false,
        ), // skip git repos
      );
      final runner = SkillsCommandRunner('skills', 'Test')
        ..addCommand(getCommand);

      await runner.run([
        'get',
        '--directory',
        projectPath,
        '--ide',
        Ide.generic.cliName,
      ]);

      expect(
        fakeDialogSupport.allInitialSelected.first,
        equals({0, 1}),
        reason: 'then all packages should be selected by default',
      );
      expect(
        fakeDialogSupport.allInitialSelected.last,
        isEmpty,
        reason: 'then new skills should not be selected by default',
      );

      final dep1SkillDir = Directory(
        p.join(skillsAdapter.skillsDirectory, 'dep1-skill'),
      );
      final dep2SkillDir = Directory(
        p.join(skillsAdapter.skillsDirectory, 'dep2-skill'),
      );

      expect(await dep1SkillDir.exists(), isTrue);
      expect(await dep2SkillDir.exists(), isFalse);

      final manifestFile = File(SkillManifest.pathIn(projectPath));
      expect(await manifestFile.exists(), isTrue);

      final manifest = await SkillManifest.loadOrEmpty(manifestFile);
      final skillNames = manifest
          .allSkillsForIde(Ide.generic.cliName)
          .map((e) => e.name)
          .toSet();
      expect(skillNames, contains('dep1-skill'));
      expect(skillNames, isNot(contains('dep2-skill')));
    });

    test(
      'when running `skills get --package dep1` (non-interactive) then only dep1 '
      'should be installed',
      () async {
        final getCommand = GetCommand(
          dialogSupport: null,
          gitRunner: GitRunner(isAvailableOverride: () async => false),
        );
        final runner = SkillsCommandRunner('skills', 'Test')
          ..addCommand(getCommand);

        await runner.run([
          'get',
          '--directory',
          projectPath,
          '--ide',
          Ide.generic.cliName,
          '--package',
          'dep1',
          '--all', // install all skills from dep1
        ]);

        final dep1SkillDir = Directory(
          p.join(skillsAdapter.skillsDirectory, 'dep1-skill'),
        );
        final dep2SkillDir = Directory(
          p.join(skillsAdapter.skillsDirectory, 'dep2-skill'),
        );

        expect(await dep1SkillDir.exists(), isTrue);
        expect(await dep2SkillDir.exists(), isFalse);
      },
    );

    test('when running `skills get --all` (non-interactive) then all skills '
        'should be installed', () async {
      final getCommand = GetCommand(
        dialogSupport: null,
        gitRunner: GitRunner(isAvailableOverride: () async => false),
      );
      final runner = SkillsCommandRunner('skills', 'Test')
        ..addCommand(getCommand);

      await runner.run([
        'get',
        '--directory',
        projectPath,
        '--ide',
        Ide.generic.cliName,
        '--all',
      ]);

      final dep1SkillDir = Directory(
        p.join(skillsAdapter.skillsDirectory, 'dep1-skill'),
      );
      final dep2SkillDir = Directory(
        p.join(skillsAdapter.skillsDirectory, 'dep2-skill'),
      );

      expect(await dep1SkillDir.exists(), isTrue);
      expect(await dep2SkillDir.exists(), isTrue);
    });

    test('when running `skills get` without package arguments and NO dialog '
        'support then no skills should be installed', () async {
      final getCommand = GetCommand(
        dialogSupport: null,
        gitRunner: GitRunner(isAvailableOverride: () async => false),
      );
      final runner = SkillsCommandRunner('skills', 'Test')
        ..addCommand(getCommand);

      await runner.run([
        'get',
        '--directory',
        projectPath,
        '--ide',
        Ide.generic.cliName,
      ]);

      final dep1SkillDir = Directory(
        p.join(skillsAdapter.skillsDirectory, 'dep1-skill'),
      );
      final dep2SkillDir = Directory(
        p.join(skillsAdapter.skillsDirectory, 'dep2-skill'),
      );

      expect(await dep1SkillDir.exists(), isFalse);
      expect(await dep2SkillDir.exists(), isFalse);
    });

    test(
      'when running `skills get --package dep3 --all` and dep3 has no skills '
      'then it should log that no skills were found in dep3',
      () async {
        final logMessages = <String>[];
        final subscription = Logger('skills get').onRecord.listen((r) {
          logMessages.add(r.message);
        });

        final getCommand = GetCommand(
          dialogSupport: null,
          gitRunner: GitRunner(isAvailableOverride: () async => false),
        );
        final runner = SkillsCommandRunner('skills', 'Test')
          ..addCommand(getCommand);

        await runner.run([
          'get',
          '--directory',
          projectPath,
          '--ide',
          Ide.generic.cliName,
          '--package',
          'dep3',
          '--all',
        ]);

        await subscription.cancel();

        expect(
          logMessages,
          contains('No skills found in the given source package:dep3.'),
        );
      },
    );

    test(
      'when running `skills get --package dep1` it does not uninstall dep2 skills',
      () async {
        final getCommand = GetCommand(
          dialogSupport: fakeDialogSupport,
          gitRunner: GitRunner(isAvailableOverride: () async => false),
        );
        final runner = SkillsCommandRunner('skills', 'Test')
          ..addCommand(getCommand);

        // First, install both dep1 and dep2 skills
        fakeDialogSupport.multiSelectResults.addAll([
          {0, 1}, // select both dep1 and dep2
          {0}, // select dep1-skill
          {0}, // select dep2-skill
        ]);

        await runner.run([
          'get',
          '--directory',
          projectPath,
          '--ide',
          Ide.generic.cliName,
        ]);

        // Verify both are installed
        await d.dir('project', [
          d.dir('.agents', [
            d.dir('skills', [d.dir('dep1-skill'), d.dir('dep2-skill')]),
          ]),
        ]).validate();

        fakeDialogSupport.reset();

        // Now run `skills get --package dep1 --all` (to skip prompt)
        await runner.run([
          'get',
          '--directory',
          projectPath,
          '--ide',
          Ide.generic.cliName,
          '--package',
          'dep1',
          '--all',
        ]);

        // Verify dep2-skill is STILL installed
        await d.dir('project', [
          d.dir('.agents', [
            d.dir('skills', [d.dir('dep1-skill'), d.dir('dep2-skill')]),
          ]),
        ]).validate();
      },
    );
  });
}
