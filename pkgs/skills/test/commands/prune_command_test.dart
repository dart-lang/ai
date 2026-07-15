import 'dart:io';

import 'package:logging/logging.dart';
import 'package:skills/src/commands/skills_command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:skills/src/commands/prune_command.dart';
import 'package:skills/src/models/skill_manifest.dart';
import '../fake_dialog_support.dart';
import '../utils.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  setUpAll(() {
    Logger.root.onRecord.listen((r) => printOnFailure(r.toString()));
  });

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

        await d.dir('pkg_a', [pubspec('pkg_a')]).create(testRootPath);

        await d
            .dir('project', [
              pubspec('my_app', dependencies: [.new('pkg_a')]),
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
            ])
            .create(testRootPath);

        final projectPath = p.join(testRootPath, 'project');

        final manifest = SkillManifest(
          installations: {
            'cursor': {
              'package:pkg_a': SkillsEntry(
                skills: [
                  InstalledSkillEntry(
                    name: 'pkg_a-skill-1',
                    installedAt: DateTime.utc(2026),
                  ),
                ],
              ),
              'package:pkg_b': SkillsEntry(
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
        final runner = SkillsCommandRunner('skills', 'Test')
          ..addCommand(pruneCommand);
        await runner.run([
          'prune',
          '--directory',
          projectPath,
          '--agent',
          'cursor',
        ]);

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
        expect(
          loaded!.sourceUrisForAgent('cursor').keys,
          contains('package:pkg_a'),
        );
        expect(
          loaded.sourceUrisForAgent('cursor').keys,
          isNot(contains('package:pkg_b')),
        );
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

        await d
            .dir('project', [
              pubspec('my_app'),
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
            ])
            .create(testRootPath);

        final projectPath = p.join(testRootPath, 'project');
        final manifest = SkillManifest(
          installations: {
            'cursor': {
              'package:old_pkg': SkillsEntry(
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
        final runner = SkillsCommandRunner('skills', 'Test')
          ..addCommand(pruneCommand);
        await runner.run([
          'prune',
          '--directory',
          projectPath,
          '--agent',
          'cursor',
        ]);

        expect(
          await Directory('$projectPath/.cursor/skills/old_pkg-skill').exists(),
          isFalse,
        );
        final dartSkillsDir = Directory(
          p.join(projectPath, SkillManifest.cacheDirPath),
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

      await d
          .dir('no_skills_project', [
            pubspec('my_app'),
            d.dir('.cursor', [d.dir('skills')]),
          ])
          .create(testRootPath);

      final projectPath = p.join(testRootPath, 'no_skills_project');

      final pruneCommand = PruneCommand(dialogSupport: FakeDialogSupport());
      final runner = SkillsCommandRunner('skills', 'Test')
        ..addCommand(pruneCommand);
      await runner.run(['prune', '--directory', projectPath]);

      expect(File(SkillManifest.pathIn(projectPath)).existsSync(), isFalse);
    });

    test('when --agent is set then only that agent is pruned', () async {
      final testRootPath = p.join(
        Directory.systemTemp.path,
        'skills_prune_test_${DateTime.now().millisecondsSinceEpoch}',
      );
      Directory(testRootPath).createSync();
      addTearDown(() async {
        await Directory(testRootPath).delete(recursive: true);
      });

      await d.dir('pkg_a', [pubspec('pkg_a')]).create(testRootPath);

      await d
          .dir('project', [
            pubspec('my_app', dependencies: [.new('pkg_a')]),
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
          ])
          .create(testRootPath);

      final projectPath = p.join(testRootPath, 'project');

      final manifest = SkillManifest(
        installations: {
          'cursor': {
            'package:pkg_a': SkillsEntry(
              skills: [
                InstalledSkillEntry(
                  name: 'pkg_a-skill',
                  installedAt: DateTime.utc(2026),
                ),
              ],
            ),
            'package:unref_pkg': SkillsEntry(
              skills: [
                InstalledSkillEntry(
                  name: 'unref-skill',
                  installedAt: DateTime.utc(2026),
                ),
              ],
            ),
          },
          'claude': {
            'package:pkg_a': SkillsEntry(
              skills: [
                InstalledSkillEntry(
                  name: 'pkg_a-skill',
                  installedAt: DateTime.utc(2026),
                ),
              ],
            ),
            'package:unref_pkg': SkillsEntry(
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
      final runner = SkillsCommandRunner('skills', 'Test')
        ..addCommand(pruneCommand);
      await runner.run([
        'prune',
        '--directory',
        projectPath,
        '--agent',
        'cursor',
      ]);

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
      expect(
        loaded!.sourceUrisForAgent('cursor').keys,
        contains('package:pkg_a'),
      );
      expect(
        loaded.sourceUrisForAgent('cursor').keys,
        isNot(contains('package:unref_pkg')),
      );
      expect(
        loaded.sourceUrisForAgent('claude').keys,
        containsAll(['package:pkg_a', 'package:unref_pkg']),
      );
    });
  });
}
