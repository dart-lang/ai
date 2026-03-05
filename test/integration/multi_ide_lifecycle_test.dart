import 'dart:io';

import 'package:skills/src/core/skill_installer.dart';
import 'package:skills/src/core/skill_scanner.dart';
import 'package:skills/src/ide/ide.dart';
import 'package:skills/src/models/skill_manifest.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  late List<ScannedSkill> pkgASkills;
  late List<ScannedSkill> pkgBSkills;

  setUp(() async {
    // Source packages with skills.
    await d.dir('pkg_a', [
      d.dir('skills', [
        d.dir('pkg_a-code-gen', [
          d.file('SKILL.md', '''
---
name: pkg_a-code-gen
description: Code generation skill.
---

# Code Generation

Instructions for code generation.
'''),
        ]),
      ]),
    ]).create();

    await d.dir('pkg_b', [
      d.dir('skills', [
        d.dir('pkg_b-testing', [
          d.file('SKILL.md', '''
---
name: pkg_b-testing
description: Testing skill.
---

# Testing

Instructions for testing.
'''),
        ]),
        d.dir('pkg_b-debugging', [
          d.file('SKILL.md', '''
---
name: pkg_b-debugging
description: Debugging skill.
---

# Debugging

Instructions for debugging.
'''),
        ]),
      ]),
    ]).create();

    pkgASkills = [
      ScannedSkill(
        packageName: 'pkg_a',
        skillName: 'pkg_a-code-gen',
        skillPath: d.path('pkg_a/skills/pkg_a-code-gen'),
      ),
    ];

    pkgBSkills = [
      ScannedSkill(
        packageName: 'pkg_b',
        skillName: 'pkg_b-testing',
        skillPath: d.path('pkg_b/skills/pkg_b-testing'),
      ),
      ScannedSkill(
        packageName: 'pkg_b',
        skillName: 'pkg_b-debugging',
        skillPath: d.path('pkg_b/skills/pkg_b-debugging'),
      ),
    ];
  });

  group('Given skills installed to Cursor and Antigravity', () {
    late String rootPath;
    late SkillManifest manifest;

    setUp(() async {
      await d.dir('project', [
        d.dir('.cursor', [d.dir('skills')]),
        d.dir('.agent', [d.dir('skills')]),
      ]).create();

      rootPath = d.path('project');
      manifest = const SkillManifest();

      const installer = SkillInstaller();
      var result = await installer.installSkillsForIde(
        ide: Ide.cursor,
        rootPath: rootPath,
        skills: [...pkgASkills, ...pkgBSkills],
        manifest: manifest,
      );
      manifest = result.manifest;
      result = await installer.installSkillsForIde(
        ide: Ide.antigravity,
        rootPath: rootPath,
        skills: [...pkgASkills, ...pkgBSkills],
        manifest: manifest,
      );
      manifest = result.manifest;
    });

    test('when removing all then both IDEs are cleaned up', () async {
      // Verify files exist before removal.
      expect(
        Directory('$rootPath/.cursor/skills/pkg_a-code-gen').existsSync(),
        isTrue,
      );
      expect(
        Directory('$rootPath/.agent/skills/pkg_a-code-gen').existsSync(),
        isTrue,
      );

      manifest = await const SkillInstaller().removeAllSkills(
        rootPath: rootPath,
        manifest: manifest,
      );

      // Verify all skill directories are gone.
      expect(
        Directory('$rootPath/.cursor/skills/pkg_a-code-gen').existsSync(),
        isFalse,
      );
      expect(
        Directory('$rootPath/.cursor/skills/pkg_b-testing').existsSync(),
        isFalse,
      );
      expect(
        Directory('$rootPath/.cursor/skills/pkg_b-debugging').existsSync(),
        isFalse,
      );
      expect(
        Directory('$rootPath/.agent/skills/pkg_a-code-gen').existsSync(),
        isFalse,
      );
      expect(
        Directory('$rootPath/.agent/skills/pkg_b-testing').existsSync(),
        isFalse,
      );
      expect(
        Directory('$rootPath/.agent/skills/pkg_b-debugging').existsSync(),
        isFalse,
      );

      expect(manifest.isEmpty, isTrue);
    });

    test('when removing one IDE then the other remains intact', () async {
      // Remove only Cursor.
      final result = await const SkillInstaller().removeSkillsForIde(
        ide: Ide.cursor,
        rootPath: rootPath,
        manifest: manifest,
      );
      manifest = result.manifest;

      // Cursor files gone.
      expect(
        Directory('$rootPath/.cursor/skills/pkg_a-code-gen').existsSync(),
        isFalse,
      );
      expect(
        Directory('$rootPath/.cursor/skills/pkg_b-testing').existsSync(),
        isFalse,
      );

      // Antigravity files still present.
      expect(
        Directory('$rootPath/.agent/skills/pkg_a-code-gen').existsSync(),
        isTrue,
      );
      expect(
        Directory('$rootPath/.agent/skills/pkg_b-testing').existsSync(),
        isTrue,
      );

      expect(manifest.allIdes, equals(['antigravity']));
      expect(manifest.packagesForIde('antigravity'), hasLength(2));
    });

    test(
      'when removing one package from all IDEs then other package remains',
      () async {
        // Remove pkg_a from both IDEs.
        const installer = SkillInstaller();
        for (final ideName in manifest.allIdes.toList()) {
          final ide = Ide.fromCliName(ideName)!;
          final result = await installer.removeSkillsForIde(
            ide: ide,
            rootPath: rootPath,
            manifest: manifest,
            packageName: 'pkg_a',
          );
          manifest = result.manifest;
        }

        // pkg_a skills gone from both IDEs.
        expect(
          Directory('$rootPath/.cursor/skills/pkg_a-code-gen').existsSync(),
          isFalse,
        );
        expect(
          Directory('$rootPath/.agent/skills/pkg_a-code-gen').existsSync(),
          isFalse,
        );

        // pkg_b skills still present in both IDEs.
        expect(
          Directory('$rootPath/.cursor/skills/pkg_b-testing').existsSync(),
          isTrue,
        );
        expect(
          Directory('$rootPath/.agent/skills/pkg_b-debugging').existsSync(),
          isTrue,
        );

        expect(manifest.packagesForIde('cursor'), contains('pkg_b'));
        expect(manifest.packagesForIde('antigravity'), contains('pkg_b'));
        expect(manifest.packagesForIde('cursor'), isNot(contains('pkg_a')));
      },
    );
  });

  group('Given skills installed then manually deleted from disk', () {
    late String rootPath;
    late SkillManifest manifest;

    setUp(() async {
      await d.dir('project', [
        d.dir('.cursor', [d.dir('skills')]),
        d.dir('.agent', [d.dir('skills')]),
      ]).create();

      rootPath = d.path('project');
      manifest = const SkillManifest();

      const installer = SkillInstaller();
      var result = await installer.installSkillsForIde(
        ide: Ide.cursor,
        rootPath: rootPath,
        skills: pkgASkills,
        manifest: manifest,
      );
      manifest = result.manifest;
      result = await installer.installSkillsForIde(
        ide: Ide.antigravity,
        rootPath: rootPath,
        skills: pkgASkills,
        manifest: manifest,
      );
      manifest = result.manifest;
    });

    test(
      'when remove all is called then manifest cleans up without error',
      () async {
        // Manually delete the Cursor skill files from disk.
        final cursorSkillDir = Directory(
          '$rootPath/.cursor/skills/pkg_a-code-gen',
        );
        expect(cursorSkillDir.existsSync(), isTrue);
        cursorSkillDir.deleteSync(recursive: true);

        // Remove all -- should not throw even though cursor files are gone.
        manifest = await const SkillInstaller().removeAllSkills(
          rootPath: rootPath,
          manifest: manifest,
        );

        expect(manifest.isEmpty, isTrue);

        // Antigravity was removed normally.
        expect(
          Directory('$rootPath/.agent/skills/pkg_a-code-gen').existsSync(),
          isFalse,
        );
      },
    );

    test('when some skills are manually deleted then remaining are still '
        'removed correctly', () async {
      // Install a second package too.
      var result = await const SkillInstaller().installSkillsForIde(
        ide: Ide.cursor,
        rootPath: rootPath,
        skills: pkgBSkills,
        manifest: manifest,
      );
      manifest = result.manifest;

      // Manually delete pkg_a skill from cursor.
      Directory(
        '$rootPath/.cursor/skills/pkg_a-code-gen',
      ).deleteSync(recursive: true);

      // Remove all.
      manifest = await const SkillInstaller().removeAllSkills(
        rootPath: rootPath,
        manifest: manifest,
      );

      // Everything should be clean, no errors.
      expect(manifest.isEmpty, isTrue);
      expect(
        Directory('$rootPath/.cursor/skills/pkg_b-testing').existsSync(),
        isFalse,
      );
    });
  });

  group('Given skills installed to Cursor and Antigravity', () {
    late String rootPath;
    late SkillManifest manifest;

    setUp(() async {
      await d.dir('project2', [
        d.dir('.cursor', [d.dir('skills')]),
        d.dir('.agent', [d.dir('skills')]),
      ]).create();

      rootPath = d.path('project2');
      manifest = const SkillManifest();

      const installer = SkillInstaller();
      var result = await installer.installSkillsForIde(
        ide: Ide.cursor,
        rootPath: rootPath,
        skills: pkgASkills,
        manifest: manifest,
      );
      manifest = result.manifest;
      result = await installer.installSkillsForIde(
        ide: Ide.antigravity,
        rootPath: rootPath,
        skills: pkgASkills,
        manifest: manifest,
      );
      manifest = result.manifest;
    });

    test('when reinstalling to one IDE then the other is untouched', () async {
      // Reinstall to Cursor only (simulating `skills get --ide cursor`).
      // SkillInstaller removes existing before installing.
      final result = await const SkillInstaller().installSkillsForIde(
        ide: Ide.cursor,
        rootPath: rootPath,
        skills: pkgASkills,
        manifest: manifest,
      );
      manifest = result.manifest;

      // Cursor reinstalled.
      expect(
        Directory('$rootPath/.cursor/skills/pkg_a-code-gen').existsSync(),
        isTrue,
      );

      // Antigravity untouched.
      expect(
        Directory('$rootPath/.agent/skills/pkg_a-code-gen').existsSync(),
        isTrue,
      );

      expect(manifest.allIdes, containsAll(['cursor', 'antigravity']));
    });
  });

  group('Given skills installed to Cursor and Claude', () {
    late String rootPath;
    late SkillManifest manifest;

    setUp(() async {
      await d.dir('project3', [
        d.dir('.cursor', [d.dir('skills')]),
        d.dir('.claude', [d.dir('rules')]),
      ]).create();

      rootPath = d.path('project3');
      manifest = const SkillManifest();

      const installer = SkillInstaller();
      var result = await installer.installSkillsForIde(
        ide: Ide.cursor,
        rootPath: rootPath,
        skills: [...pkgASkills, ...pkgBSkills],
        manifest: manifest,
      );
      manifest = result.manifest;
      result = await installer.installSkillsForIde(
        ide: Ide.claude,
        rootPath: rootPath,
        skills: [...pkgASkills, ...pkgBSkills],
        manifest: manifest,
      );
      manifest = result.manifest;
    });

    test('when listing then manifest reports both IDEs correctly', () {
      expect(manifest.allIdes, containsAll(['cursor', 'claude']));

      expect(manifest.packagesForIde('cursor'), hasLength(2));
      expect(manifest.packagesForIde('claude'), hasLength(2));

      expect(manifest.allSkillsForIde('cursor'), hasLength(3));
      expect(manifest.allSkillsForIde('claude'), hasLength(3));

      expect(manifest.allSkills, hasLength(6));
    });

    test('when removing all then both Agent Skills and Rules files are '
        'cleaned up', () async {
      // Verify mixed format files exist.
      expect(
        Directory('$rootPath/.cursor/skills/pkg_a-code-gen').existsSync(),
        isTrue,
      );
      expect(
        File('$rootPath/.claude/rules/pkg_a-code-gen.md').existsSync(),
        isTrue,
      );

      manifest = await const SkillInstaller().removeAllSkills(
        rootPath: rootPath,
        manifest: manifest,
      );

      // Agent Skills directories cleaned.
      expect(
        Directory('$rootPath/.cursor/skills/pkg_a-code-gen').existsSync(),
        isFalse,
      );
      expect(
        Directory('$rootPath/.cursor/skills/pkg_b-testing').existsSync(),
        isFalse,
      );

      // Rules files cleaned.
      expect(
        File('$rootPath/.claude/rules/pkg_a-code-gen.md').existsSync(),
        isFalse,
      );
      expect(
        File('$rootPath/.claude/rules/pkg_b-testing.md').existsSync(),
        isFalse,
      );

      expect(manifest.isEmpty, isTrue);
    });
  });

  group('Given manifest saved to and loaded from disk', () {
    test(
      'when round-tripping multi-IDE manifest then all data preserved',
      () async {
        await d.dir('persist_project').create();
        final rootPath = d.path('persist_project');

        var manifest = const SkillManifest();
        manifest = manifest.withPackage(
          'cursor',
          'pkg_a',
          PackageSkillsEntry(
            skills: [
              InstalledSkillEntry(
                name: 'pkg_a-code-gen',
                installedAt: DateTime.utc(2026, 3, 1),
              ),
            ],
          ),
        );
        manifest = manifest.withPackage(
          'antigravity',
          'pkg_a',
          PackageSkillsEntry(
            skills: [
              InstalledSkillEntry(
                name: 'pkg_a-code-gen',
                installedAt: DateTime.utc(2026, 3, 1),
              ),
            ],
          ),
        );
        manifest = manifest.withPackage(
          'claude',
          'pkg_b',
          PackageSkillsEntry(
            skills: [
              InstalledSkillEntry(
                name: 'pkg_b-testing',
                installedAt: DateTime.utc(2026, 3, 1),
              ),
            ],
          ),
        );

        final file = File(SkillManifest.pathIn(rootPath));
        await manifest.save(file);

        final loaded = await SkillManifest.load(file);
        expect(loaded, isNotNull);
        expect(
          loaded!.allIdes.toSet(),
          equals({'cursor', 'antigravity', 'claude'}),
        );
        expect(loaded.packagesForIde('cursor')['pkg_a']!.skills, hasLength(1));
        expect(
          loaded.packagesForIde('antigravity')['pkg_a']!.skills,
          hasLength(1),
        );
        expect(loaded.packagesForIde('claude')['pkg_b']!.skills, hasLength(1));
      },
    );
  });
}
