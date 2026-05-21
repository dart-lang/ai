import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:skills/src/commands/prune_command.dart';
import 'package:skills/src/models/skill_manifest.dart';
import '../fake_dialog_support.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  group('Prune command', () {
    test(
      'removes only unreferenced packages when manifest has pkg_a and pkg_b but deps only pkg_a',
      () async {
        final testRootPath = p.join(
          Directory.systemTemp.path,
          'skills_prune_test_${DateTime.now().millisecondsSinceEpoch}',
        );
        Directory(testRootPath).createSync();
        addTearDown(() async {
          await Directory(testRootPath).delete(recursive: true);
        });

        await d.dir('pkg_a', [
          d.dir('lib', [d.file('pkg_a.dart', '')])
        ]).create(testRootPath);

        await d.dir('project', [
          d.file('pubspec.yaml', '''
name: my_app
environment:
  sdk: ^3.0.0
'''),
          d.dir('.dart_tool', [
            d.file(
              'package_config.json',
              jsonEncode({
                'configVersion': 2,
                'packages': [
                  {'name': 'my_app', 'rootUri': '../', 'packageUri': 'lib/'},
                  {
                    'name': 'pkg_a',
                    'rootUri': '../../pkg_a',
                    'packageUri': 'lib/',
                  },
                ],
              }),
            ),
          ]),
          d.dir('.cursor', [
            d.dir('skills', [
              d.dir('pkg_a-skill-1', [
                d.file(
                  'SKILL.md',
                  '---\nname: pkg_a-skill-1\ndescription: a\n---\n',
                ),
              ]),
              d.dir('pkg_b-skill-2', [
                d.file(
                  'SKILL.md',
                  '---\nname: pkg_b-skill-2\ndescription: b\n---\n',
                ),
              ]),
            ]),
          ]),
        ]).create(testRootPath);

        final projectPath = p.join(testRootPath, 'project');

        final manifest = SkillManifest(
          installations: {
            'cursor': {
              'pkg_a': PackageSkillsEntry(
                skills: [
                  InstalledSkillEntry(
                    name: 'pkg_a-skill-1',
                    installedAt: DateTime.utc(2026),
                  ),
                ],
              ),
              'pkg_b': PackageSkillsEntry(
                skills: [
                  InstalledSkillEntry(
                    name: 'pkg_b-skill-2',
                    installedAt: DateTime.utc(2026),
                  ),
                ],
              ),
            },
          },
        );
        await manifest.save(File(SkillManifest.pathIn(projectPath)));

        final pruneCommand = PruneCommand(dialogSupport: FakeDialogSupport());
        final runner = CommandRunner<void>('skills', 'Test')
          ..addCommand(pruneCommand);
        await runner
            .run(['prune', '--directory', projectPath, '--ide', 'cursor']);

        expect(
          await Directory('$projectPath/.cursor/skills/pkg_a-skill-1').exists(),
          isTrue,
        );
        expect(
          await Directory('$projectPath/.cursor/skills/pkg_b-skill-2').exists(),
          isFalse,
        );

        final loaded = await SkillManifest.loadFromRoot(projectPath);
        expect(loaded, isNotNull);
        expect(loaded!.packagesForIde('cursor').keys, contains('pkg_a'));
        expect(loaded.packagesForIde('cursor').keys, isNot(contains('pkg_b')));
      },
    );

    test(
      'when no referenced packages then all tracked skills are removed',
      () async {
        final testRootPath = p.join(
          Directory.systemTemp.path,
          'skills_prune_test_${DateTime.now().millisecondsSinceEpoch}',
        );
        Directory(testRootPath).createSync();
        addTearDown(() async {
          await Directory(testRootPath).delete(recursive: true);
        });

        await d.dir('project', [
          d.file('pubspec.yaml', '''
name: my_app
environment:
  sdk: ^3.0.0
'''),
          d.dir('.dart_tool', [
            d.file(
              'package_config.json',
              jsonEncode({
                'configVersion': 2,
                'packages': [
                  {'name': 'my_app', 'rootUri': '../', 'packageUri': 'lib/'},
                ],
              }),
            ),
          ]),
          d.dir('.cursor', [
            d.dir('skills', [
              d.dir('old_pkg-skill', [
                d.file(
                  'SKILL.md',
                  '---\nname: old_pkg-skill\ndescription: x\n---\n',
                ),
              ]),
            ]),
          ]),
        ]).create(testRootPath);

        final projectPath = p.join(testRootPath, 'project');
        final manifest = SkillManifest(
          installations: {
            'cursor': {
              'old_pkg': PackageSkillsEntry(
                skills: [
                  InstalledSkillEntry(
                    name: 'old_pkg-skill',
                    installedAt: DateTime.utc(2026),
                  ),
                ],
              ),
            },
          },
        );
        await manifest.save(File(SkillManifest.pathIn(projectPath)));

        final pruneCommand = PruneCommand(dialogSupport: FakeDialogSupport());
        final runner = CommandRunner<void>('skills', 'Test')
          ..addCommand(pruneCommand);
        await runner
            .run(['prune', '--directory', projectPath, '--ide', 'cursor']);

        expect(
          await Directory('$projectPath/.cursor/skills/old_pkg-skill').exists(),
          isFalse,
        );
        final dartSkillsDir = Directory(
          p.join(projectPath, SkillManifest.dirName),
        );
        expect(await dartSkillsDir.exists(), isFalse);
      },
    );

    test('when no managed skills then prints message and exits', () async {
      final testRootPath = p.join(
        Directory.systemTemp.path,
        'skills_prune_test_${DateTime.now().millisecondsSinceEpoch}',
      );
      Directory(testRootPath).createSync();
      addTearDown(() async {
        await Directory(testRootPath).delete(recursive: true);
      });

      await d.dir('no_skills_project', [
        d.file('pubspec.yaml', '''
name: my_app
environment:
  sdk: ^3.0.0
'''),
        d.dir('.dart_tool', [
          d.file(
            'package_config.json',
            jsonEncode({
              'configVersion': 2,
              'packages': [
                {'name': 'my_app', 'rootUri': '../', 'packageUri': 'lib/'},
              ],
            }),
          ),
        ]),
        d.dir('.cursor', [d.dir('skills')]),
      ]).create(testRootPath);

      final projectPath = p.join(testRootPath, 'no_skills_project');

      final pruneCommand = PruneCommand(dialogSupport: FakeDialogSupport());
      final runner = CommandRunner<void>('skills', 'Test')
        ..addCommand(pruneCommand);
      await runner.run(['prune', '--directory', projectPath]);

      expect(File(SkillManifest.pathIn(projectPath)).existsSync(), isFalse);
    });

    test(
      'when --ide is set then only that IDE is pruned',
      () async {
        final testRootPath = p.join(
          Directory.systemTemp.path,
          'skills_prune_test_${DateTime.now().millisecondsSinceEpoch}',
        );
        Directory(testRootPath).createSync();
        addTearDown(() async {
          await Directory(testRootPath).delete(recursive: true);
        });

        await d.dir('pkg_a', [
          d.dir('lib', [d.file('pkg_a.dart', '')])
        ]).create(testRootPath);

        await d.dir('project', [
          d.file('pubspec.yaml', '''
name: my_app
environment:
  sdk: ^3.0.0
'''),
          d.dir('.dart_tool', [
            d.file(
              'package_config.json',
              jsonEncode({
                'configVersion': 2,
                'packages': [
                  {'name': 'my_app', 'rootUri': '../', 'packageUri': 'lib/'},
                  {
                    'name': 'pkg_a',
                    'rootUri': '../../pkg_a',
                    'packageUri': 'lib/',
                  },
                ],
              }),
            ),
          ]),
          d.dir('.cursor', [
            d.dir('skills', [
              d.dir('pkg_a-skill', [
                d.file(
                  'SKILL.md',
                  '---\nname: pkg_a-skill\ndescription: a\n---\n',
                ),
              ]),
              d.dir('unref-skill', [
                d.file(
                  'SKILL.md',
                  '---\nname: unref-skill\ndescription: u\n---\n',
                ),
              ]),
            ]),
          ]),
          d.dir('.claude', [
            d.dir('skills', [
              d.dir('pkg_a-skill', [
                d.file(
                  'SKILL.md',
                  '---\nname: pkg_a-skill\ndescription: a\n---\n',
                ),
              ]),
              d.dir('unref-skill', [
                d.file(
                  'SKILL.md',
                  '---\nname: unref-skill\ndescription: u\n---\n',
                ),
              ]),
            ]),
          ]),
        ]).create(testRootPath);

        final projectPath = p.join(testRootPath, 'project');

        final manifest = SkillManifest(
          installations: {
            'cursor': {
              'pkg_a': PackageSkillsEntry(
                skills: [
                  InstalledSkillEntry(
                    name: 'pkg_a-skill',
                    installedAt: DateTime.utc(2026),
                  ),
                ],
              ),
              'unref_pkg': PackageSkillsEntry(
                skills: [
                  InstalledSkillEntry(
                    name: 'unref-skill',
                    installedAt: DateTime.utc(2026),
                  ),
                ],
              ),
            },
            'claude': {
              'pkg_a': PackageSkillsEntry(
                skills: [
                  InstalledSkillEntry(
                    name: 'pkg_a-skill',
                    installedAt: DateTime.utc(2026),
                  ),
                ],
              ),
              'unref_pkg': PackageSkillsEntry(
                skills: [
                  InstalledSkillEntry(
                    name: 'unref-skill',
                    installedAt: DateTime.utc(2026),
                  ),
                ],
              ),
            },
          },
        );
        await manifest.save(File(SkillManifest.pathIn(projectPath)));

        final pruneCommand = PruneCommand(dialogSupport: FakeDialogSupport());
        final runner = CommandRunner<void>('skills', 'Test')
          ..addCommand(pruneCommand);
        await runner
            .run(['prune', '--directory', projectPath, '--ide', 'cursor']);

        expect(
          Directory('$projectPath/.cursor/skills/unref-skill').existsSync(),
          isFalse,
        );
        expect(
          Directory('$projectPath/.claude/skills/unref-skill').existsSync(),
          isTrue,
        );

        final loaded = await SkillManifest.loadFromRoot(projectPath);
        expect(loaded, isNotNull);
        expect(loaded!.packagesForIde('cursor').keys, contains('pkg_a'));
        expect(
            loaded.packagesForIde('cursor').keys, isNot(contains('unref_pkg')));
        expect(loaded.packagesForIde('claude').keys,
            containsAll(['pkg_a', 'unref_pkg']));
      },
    );
  });
}
