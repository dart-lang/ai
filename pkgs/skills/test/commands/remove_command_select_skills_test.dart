import 'dart:io';

import 'package:logging/logging.dart';
import 'package:skills/src/commands/remove_command.dart';
import 'package:skills/src/commands/skills_command_runner.dart';
import 'package:skills/src/models/skill_manifest.dart';
import '../fake_dialog_support.dart';
import '../utils.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  group('Given a project with installed skills for dep1 and dep2', () {
    late String projectPath;
    late FakeDialogSupport fakeDialogSupport;
    late SkillManifest manifest;
    late SkillsCommandRunner runner;

    setUpAll(() {
      Logger.root.onRecord.listen((r) => printOnFailure(r.toString()));
    });

    setUp(() async {
      fakeDialogSupport = FakeDialogSupport();
      final removeCommand = RemoveCommand(dialogSupport: fakeDialogSupport);
      runner = SkillsCommandRunner('skills', 'test')..addCommand(removeCommand);

      await d.dir('dep1', [pubspec('dep1')]).create();
      await d.dir('dep2', [pubspec('dep2')]).create();

      final projectRootDir = d.dir('project', [
        pubspec('test_app', dependencies: [.new('dep1'), .new('dep2')]),
        d.dir('.cursor', [
          d.dir('skills', [
            d.dir('dep1-skill-1', [d.file('SKILL.md', 'content')]),
            d.dir('dep1-skill-2', [d.file('SKILL.md', 'content')]),
            d.dir('dep2-skill-1', [d.file('SKILL.md', 'content')]),
            d.dir('dep2-skill-2', [d.file('SKILL.md', 'content')]),
          ]),
        ]),
      ]);
      await projectRootDir.create();

      projectPath = projectRootDir.io.path;
      await Process.run('dart', ['pub', 'get'], workingDirectory: projectPath);

      manifest = SkillManifest(
        installations: {
          'cursor': {
            'package:dep1': SkillsEntry(
              skills: [
                InstalledSkillEntry(
                  name: 'dep1-skill-1',
                  installedAt: DateTime.utc(2026),
                ),
                InstalledSkillEntry(
                  name: 'dep1-skill-2',
                  installedAt: DateTime.utc(2026),
                ),
              ],
            ),
            'package:dep2': SkillsEntry(
              skills: [
                InstalledSkillEntry(
                  name: 'dep2-skill-1',
                  installedAt: DateTime.utc(2026),
                ),
                InstalledSkillEntry(
                  name: 'dep2-skill-2',
                  installedAt: DateTime.utc(2026),
                ),
              ],
            ),
          },
        },
      );

      await manifest.save(File(SkillManifest.pathIn(projectPath)));
    });

    test(
      'when running `skills remove --package dep1` (interactive) and user selects '
      'only dep1-skill-1 for removal, then only dep1-skill-1 is removed',
      () async {
        // We skip package selection (because of --package).
        // We have 2 skills in dep1, so we prompt.
        // Index 0 is dep1-skill-1, index 1 is dep1-skill-2 (sorted).
        // We select only index 0 (dep1-skill-1) to remove.
        fakeDialogSupport.multiSelectResults.add({0});

        await runner.run([
          'remove',
          '--directory',
          projectPath,
          '--ide',
          'cursor',
          '--package',
          'dep1',
        ]);

        expect(fakeDialogSupport.allMultiSelectOptions, hasLength(1));
        expect(
          fakeDialogSupport.allMultiSelectOptions[0],
          equals(['dep1-skill-1', 'dep1-skill-2']),
        );
        expect(
          fakeDialogSupport.allTitles[0],
          equals('Select skills to remove'),
        );

        await d.dir('project', [
          d.dir('.cursor', [
            d.dir('skills', [
              d.nothing('dep1-skill-1'),
              d.dir('dep1-skill-2'), // retained!
              d.dir('dep2-skill-1'), // unaffected!
              d.dir('dep2-skill-2'), // unaffected!
            ]),
          ]),
        ]).validate();

        final updatedManifest = await SkillManifest.loadOrEmptyFromRoot(
          projectPath,
        );
        final dep1Skills = updatedManifest
            .sourceUrisForIde('cursor')['package:dep1']!
            .skills
            .map((s) => s.name)
            .toList();
        expect(dep1Skills, equals(['dep1-skill-2']));
      },
    );

    test(
      'when running `skills remove` (interactive), user selects both packages, '
      'then selects dep1-skill-1 from dep1 and dep2-skill-2 from dep2, '
      'then only those two are removed',
      () async {
        fakeDialogSupport.multiSelectResults = [
          // Select both packages dep1 and dep2 in package dialog
          {0, 1},
          // Select dep1-skill-1 and dep2-skill-2
          {0, 3},
        ];

        await runner.run([
          'remove',
          '--directory',
          projectPath,
          '--ide',
          'cursor',
        ]);

        expect(fakeDialogSupport.allMultiSelectOptions, hasLength(2));
        expect(
          fakeDialogSupport.allMultiSelectOptions[0],
          unorderedEquals(['package:dep1', 'package:dep2']),
        );
        expect(
          fakeDialogSupport.allMultiSelectOptions[1],
          equals([
            'dep1-skill-1',
            'dep1-skill-2',
            'dep2-skill-1',
            'dep2-skill-2',
          ]),
        );

        expect(
          fakeDialogSupport.allTitles[1],
          equals('Select skills to remove'),
        );

        await d.dir('project', [
          d.dir('.cursor', [
            d.dir('skills', [
              d.nothing('dep1-skill-1'), // removed!
              d.dir('dep1-skill-2'), // kept!
              d.dir('dep2-skill-1'), // kept!
              d.nothing('dep2-skill-2'), // removed!
            ]),
          ]),
        ]).validate();

        final updatedManifest = await SkillManifest.loadOrEmptyFromRoot(
          projectPath,
        );
        final dep1Skills = updatedManifest
            .sourceUrisForIde('cursor')['package:dep1']!
            .skills
            .map((s) => s.name)
            .toList();
        expect(dep1Skills, equals(['dep1-skill-2']));
        final dep2Skills = updatedManifest
            .sourceUrisForIde('cursor')['package:dep2']!
            .skills
            .map((s) => s.name)
            .toList();
        expect(dep2Skills, equals(['dep2-skill-1']));
      },
    );
  });
}
