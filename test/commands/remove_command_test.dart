import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills/src/ide/adapters/claude_adapter.dart';
import 'package:skills/src/ide/adapters/cursor_adapter.dart';
import 'package:skills/src/models/skill_manifest.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  group('Given a project with managed skills installed', () {
    late String projectPath;
    late SkillManifest manifest;

    setUp(() async {
      await d.dir('project', [
        d.dir('.cursor', [
          d.dir('skills', [
            d.dir('pkg_a-skill-1', [
              d.file(
                'SKILL.md',
                '---\nname: pkg_a-skill-1\ndescription: s1\n---\nBody 1',
              ),
            ]),
            d.dir('pkg_a-skill-2', [
              d.file(
                'SKILL.md',
                '---\nname: pkg_a-skill-2\ndescription: s2\n---\nBody 2',
              ),
            ]),
            d.dir('pkg_b-skill-3', [
              d.file(
                'SKILL.md',
                '---\nname: pkg_b-skill-3\ndescription: s3\n---\nBody 3',
              ),
            ]),
          ]),
        ]),
      ]).create();

      projectPath = d.path('project');

      manifest = SkillManifest(
        installations: {
          'cursor': {
            'pkg_a': PackageSkillsEntry(
              skills: [
                InstalledSkillEntry(
                  name: 'pkg_a-skill-1',
                  installedAt: DateTime.utc(2026),
                ),
                InstalledSkillEntry(
                  name: 'pkg_a-skill-2',
                  installedAt: DateTime.utc(2026),
                ),
              ],
            ),
            'pkg_b': PackageSkillsEntry(
              skills: [
                InstalledSkillEntry(
                  name: 'pkg_b-skill-3',
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
      'when removing a specific package then only its skills are removed',
      () async {
        final adapter = CursorAdapter(projectPath);

        final pkgEntry = manifest.packagesForIde('cursor')['pkg_a']!;
        for (final skill in pkgEntry.skills) {
          await adapter.removeSkill(skill.name);
        }
        final updated = manifest.withoutPackage('cursor', 'pkg_a');

        expect(
          await Directory('$projectPath/.cursor/skills/pkg_a-skill-1').exists(),
          isFalse,
        );
        expect(
          await Directory('$projectPath/.cursor/skills/pkg_a-skill-2').exists(),
          isFalse,
        );
        expect(
          await Directory('$projectPath/.cursor/skills/pkg_b-skill-3').exists(),
          isTrue,
        );
        expect(updated.packagesForIde('cursor'), hasLength(1));
        expect(updated.packagesForIde('cursor'), contains('pkg_b'));
      },
    );

    test('when removing all then all managed skills are removed', () async {
      final adapter = CursorAdapter(projectPath);

      for (final entry in manifest.packagesForIde('cursor').values) {
        for (final skill in entry.skills) {
          await adapter.removeSkill(skill.name);
        }
      }

      expect(
        await Directory('$projectPath/.cursor/skills/pkg_a-skill-1').exists(),
        isFalse,
      );
      expect(
        await Directory('$projectPath/.cursor/skills/pkg_b-skill-3').exists(),
        isFalse,
      );
    });

    test(
      'when removing all then .dart_skills directory is cleaned up',
      () async {
        final updated = manifest
            .withoutPackage('cursor', 'pkg_a')
            .withoutPackage('cursor', 'pkg_b');
        expect(updated.isEmpty, isTrue);

        final dartSkillsDir = Directory(
          p.join(projectPath, SkillManifest.dirName),
        );
        expect(await dartSkillsDir.exists(), isTrue);

        await SkillManifest.cleanupDir(projectPath);

        expect(await dartSkillsDir.exists(), isFalse);
      },
    );
  });

  group('Given a project with no managed skills', () {
    test('when removing then manifest remains empty', () async {
      await d.dir('empty_project', [
        d.dir('.cursor', [d.dir('skills')]),
      ]).create();

      final manifestFile = File(SkillManifest.pathIn(d.path('empty_project')));
      final manifest = await SkillManifest.load(manifestFile);

      expect(manifest, isNull);
    });
  });

  group('Given a project with multi-IDE installations (Cursor + Claude)', () {
    late String projectPath;
    late SkillManifest manifest;

    setUp(() async {
      await d.dir('multi_project', [
        d.dir('.cursor', [
          d.dir('skills', [
            d.dir('pkg-skill-a', [
              d.file(
                'SKILL.md',
                '---\nname: pkg-skill-a\ndescription: a\n---\nBody A',
              ),
            ]),
          ]),
        ]),
        d.dir('.claude', [
          d.dir('skills', [
            d.dir('pkg-skill-a', [
              d.file(
                'SKILL.md',
                '---\nname: pkg-skill-a\ndescription: a\n---\nBody A',
              ),
            ]),
          ]),
        ]),
      ]).create();

      projectPath = d.path('multi_project');

      manifest = SkillManifest(
        installations: {
          'cursor': {
            'pkg': PackageSkillsEntry(
              skills: [
                InstalledSkillEntry(
                  name: 'pkg-skill-a',
                  installedAt: DateTime.utc(2026),
                ),
              ],
            ),
          },
          'claude': {
            'pkg': PackageSkillsEntry(
              skills: [
                InstalledSkillEntry(
                  name: 'pkg-skill-a',
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
        'when removing one IDE then files for that IDE are deleted and '
        'other IDE files remain', () async {
      final cursorAdapter = CursorAdapter(projectPath);

      for (final skill in manifest.packagesForIde('cursor')['pkg']!.skills) {
        await cursorAdapter.removeSkill(skill.name);
      }
      final updated = manifest.withoutIde('cursor');

      expect(
        Directory('$projectPath/.cursor/skills/pkg-skill-a').existsSync(),
        isFalse,
      );
      expect(
        Directory('$projectPath/.claude/skills/pkg-skill-a').existsSync(),
        isTrue,
      );
      expect(updated.allIdes, equals(['claude']));
      expect(updated.packagesForIde('claude')['pkg']!.skills, hasLength(1));
    });

    test(
        'when removing all IDEs then both Cursor and Claude skill '
        'directories are deleted', () async {
      final cursorAdapter = CursorAdapter(projectPath);
      final claudeAdapter = ClaudeAdapter(projectPath);

      for (final skill in manifest.packagesForIde('cursor')['pkg']!.skills) {
        await cursorAdapter.removeSkill(skill.name);
      }
      var updated = manifest.withoutIde('cursor');

      for (final skill in updated.packagesForIde('claude')['pkg']!.skills) {
        await claudeAdapter.removeSkill(skill.name);
      }
      updated = updated.withoutIde('claude');

      expect(
        Directory('$projectPath/.cursor/skills/pkg-skill-a').existsSync(),
        isFalse,
      );
      expect(
        Directory('$projectPath/.claude/skills/pkg-skill-a').existsSync(),
        isFalse,
      );
      expect(updated.isEmpty, isTrue);
    });

    test(
        'when Claude skill directory is manually deleted then remove still '
        'cleans manifest without error', () async {
      Directory(
        '$projectPath/.claude/skills/pkg-skill-a',
      ).deleteSync(recursive: true);

      final claudeAdapter = ClaudeAdapter(projectPath);
      for (final skill in manifest.packagesForIde('claude')['pkg']!.skills) {
        await claudeAdapter.removeSkill(skill.name);
      }
      final updated = manifest.withoutIde('claude');

      expect(updated.allIdes, equals(['cursor']));
    });
  });
}
