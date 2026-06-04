import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:logging/logging.dart';
import 'package:skills/src/commands/remove_command.dart';
import 'package:skills/src/commands/skills_command_runner.dart';
import 'package:skills/src/models/skill_manifest.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import '../fake_dialog_support.dart';

void main() {
  late CommandRunner runner;
  late FakeDialogSupport fakeDialogSupport;

  setUpAll(() {
    Logger.root.onRecord.listen((r) => printOnFailure(r.toString()));
  });

  setUp(() {
    fakeDialogSupport = FakeDialogSupport();
    final removeCommand = RemoveCommand(dialogSupport: fakeDialogSupport);
    runner = SkillsCommandRunner('skills', 'test')..addCommand(removeCommand);
  });

  group('Given a project with installed skills for dep1 and dep2', () {
    late String projectPath;
    late SkillManifest manifest;

    setUp(() async {
      final projectRootDir = d.dir('project', [
        d.file('pubspec.yaml', '''
name: test_app
environment:
  sdk: ^3.0.0
'''),
        d.dir('.dart_tool', [
          d.file(
            'package_config.json',
            jsonEncode({
              'configVersion': 2,
              'packages': [
                {'name': 'test_app', 'rootUri': '../', 'packageUri': 'lib/'},
                {'name': 'dep1', 'rootUri': '../../dep1', 'packageUri': 'lib/'},
                {'name': 'dep2', 'rootUri': '../../dep2', 'packageUri': 'lib/'},
              ],
            }),
          ),
        ]),
        d.dir('.cursor', [
          d.dir('skills', [
            d.dir('dep1-skill-1', [d.file('SKILL.md', 'content')]),
            d.dir('dep1-skill-2', [d.file('SKILL.md', 'content')]),
            d.dir('dep2-skill-3', [d.file('SKILL.md', 'content')]),
          ]),
        ]),
      ]);
      await projectRootDir.create();

      projectPath = projectRootDir.io.path;

      manifest = SkillManifest(
        installations: {
          'cursor': {
            'dep1': PackageSkillsEntry(
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
            'dep2': PackageSkillsEntry(
              skills: [
                InstalledSkillEntry(
                  name: 'dep2-skill-3',
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
        'when running `skills remove --package dep1` then removes only dep1 skills',
        () async {
      fakeDialogSupport.multiSelectResults.add({0, 1});
      await runner.run([
        'remove',
        '--directory',
        projectPath,
        '--ide',
        'cursor',
        '--package',
        'dep1'
      ]);

      await d.dir('project', [
        d.dir('.cursor', [
          d.dir('skills', [
            d.nothing('dep1-skill-1'),
            d.nothing('dep1-skill-2'),
            d.dir('dep2-skill-3'),
          ]),
        ]),
        d.dir(SkillManifest.configDirPath, [
          d.file(
            'skills_config.json',
            allOf(
              isNot(contains('dep1-skill-1')),
              isNot(contains('dep1-skill-2')),
              contains('dep2-skill-3'),
            ),
          ),
        ]),
      ]).validate();
    });

    test('when running `skills remove --all` then removes all skills',
        () async {
      await runner.run(
          ['remove', '--directory', projectPath, '--ide', 'cursor', '--all']);

      await d.dir('project', [
        d.dir('.cursor', [
          d.dir('skills', [
            d.nothing('dep1-skill'),
            d.nothing('dep2-skill'),
          ]),
        ]),
        d.dir('.dart_tool', [d.nothing('skills')]),
      ]).validate();
    });

    test(
      'when removing all then cache and config directories are cleaned up',
      () async {
        await runner.run(
            ['remove', '--directory', projectPath, '--ide', 'cursor', '--all']);

        await d.dir('project', [
          d.nothing(SkillManifest.configDirPath),
          d.nothing(SkillManifest.cacheDirPath)
        ]).validate();
      },
    );
  });

  group('Given a project with no managed skills', () {
    test('when removing then manifest remains empty', () async {
      await d.dir('empty_project', [
        d.file('pubspec.yaml', '''
name: test_app
environment:
  sdk: ^3.0.0
'''),
        d.dir('.cursor', [d.dir('skills')]),
      ]).create();
      var projectPath = d.dir('empty_project').io.path;

      await runner.run(
          ['remove', '--directory', projectPath, '--ide', 'cursor', '--all']);

      final manifest =
          await SkillManifest.loadFromRoot(d.path('empty_project'));

      expect(manifest, isNull);
    });
  });

  group('Given a project with multi-IDE installations (Cursor + Claude)', () {
    late String projectPath;
    late SkillManifest manifest;

    setUp(() async {
      await d.dir('multi_project', [
        d.file('pubspec.yaml', '''
name: test_app
environment:
  sdk: ^3.0.0
'''),
        d.dir('.cursor', [
          d.dir('skills', [
            d.dir('dep1-skill', [
              d.file(
                'SKILL.md',
                '---\nname: pkg-skill\ndescription: a\n---\nBody A',
              ),
            ]),
            d.dir('dep2-skill', [
              d.file(
                'SKILL.md',
                '---\nname: dep2-skill\ndescription: a\n---\nBody A',
              ),
            ]),
          ]),
        ]),
        d.dir('.claude', [
          d.dir('skills', [
            d.dir('dep1-skill', [
              d.file(
                'SKILL.md',
                '---\nname: dep1-skill\ndescription: a\n---\nBody A',
              ),
            ]),
            d.dir('dep2-skill', [
              d.file(
                'SKILL.md',
                '---\nname: dep2-skill\ndescription: a\n---\nBody A',
              ),
            ]),
          ]),
        ]),
      ]).create();

      projectPath = d.path('multi_project');

      final dep1SkillsEntry = PackageSkillsEntry(
        skills: [
          InstalledSkillEntry(
            name: 'dep1-skill',
            installedAt: DateTime.utc(2026),
          ),
        ],
      );
      final dep2SkillsEntry = PackageSkillsEntry(
        skills: [
          InstalledSkillEntry(
            name: 'dep2-skill',
            installedAt: DateTime.utc(2026),
          ),
        ],
      );
      manifest = SkillManifest(
        installations: {
          'cursor': {'dep1': dep1SkillsEntry, 'dep2': dep2SkillsEntry},
          'claude': {'dep1': dep1SkillsEntry, 'dep2': dep2SkillsEntry},
        },
      );

      await manifest.save(File(SkillManifest.pathIn(projectPath)));
    });

    test(
        'when running `skills remove` without arguments removes the'
        'selected skills for all IDEs', () async {
      fakeDialogSupport.multiSelectResults
        ..add({0}) // select first dep (dep1)
        ..add({0}); // select first skill

      await runner.run(['remove', '--directory', projectPath]);

      await d.dir('multi_project', [
        d.dir('.cursor', [
          d.dir('skills', [
            d.nothing('dep1-skill'),
            d.dir('dep2-skill'),
          ]),
        ]),
        d.dir('.claude', [
          d.dir('skills', [
            d.nothing('dep1-skill'),
            d.dir('dep2-skill'),
          ]),
        ]),
      ]).validate();
    });

    test(
        'when running `skills remove --ide cursor --skill <skill>` removes the '
        'given skills for just cursor', () async {
      await runner.run([
        'remove',
        '--directory',
        projectPath,
        '--ide',
        'cursor',
        '--skill',
        'dep1-skill'
      ]);

      await d.dir('multi_project', [
        d.dir('.cursor', [
          d.dir('skills', [
            d.nothing('dep1-skill'),
            d.dir('dep2-skill'),
          ]),
        ]),
        d.dir('.claude', [
          d.dir('skills', [
            d.dir('dep1-skill'),
            d.dir('dep2-skill'),
          ]),
        ]),
      ]).validate();
    });

    test(
        'when running `skills remove` without arguments and NO dialog support '
        'then does nothing and prints packages', () async {
      final noDialogCommand = RemoveCommand(dialogSupport: null);
      final noDialogRunner = SkillsCommandRunner('skills', 'test')
        ..addCommand(noDialogCommand);

      await noDialogRunner
          .run(['remove', '--directory', projectPath, '--ide', 'cursor']);

      await d.dir('multi_project', [
        d.dir('.cursor', [
          d.dir('skills', [
            d.dir('dep1-skill'),
            d.dir('dep2-skill'),
          ]),
        ]),
        d.dir('.claude', [
          d.dir('skills', [
            d.dir('dep1-skill'),
            d.dir('dep2-skill'),
          ]),
        ]),
        d.dir(SkillManifest.configDirPath, [
          d.file('skills_config.json',
              allOf(contains('dep1-skill'), contains('dep2-skill'))),
        ]),
      ]).validate();
    });

    test(
        'when Claude skill directory is manually deleted then remove still '
        'cleans manifest without error', () async {
      Directory(
        '$projectPath/.claude/skills/dep1-skill',
      ).deleteSync(recursive: true);

      await runner.run([
        'remove',
        '--directory',
        projectPath,
        '--ide',
        'claude',
        '--package',
        'dep1',
        '--all' // all skills from dep1
      ]);
      final manifest = await SkillManifest.loadFromRoot(projectPath);
      expect(manifest!.packagesForIde('claude').keys,
          allOf(contains('dep2'), isNot(contains('dep1'))));
    });
  });
}
