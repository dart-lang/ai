import 'dart:io';

import 'package:logging/logging.dart';
import 'package:skills/src/core/skill_installer.dart';
import 'package:skills/src/core/skill_scanner.dart';
import 'package:skills/src/ide/ide.dart';
import '../fake_dialog_support.dart';
import 'package:skills/src/models/global_config.dart';
import 'package:skills/src/models/skill_manifest.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  late List<ScannedSkill> pkgASkills;
  late List<ScannedSkill> pkgBSkills;
  late FakeDialogSupport fakeDialogSupport;

  setUpAll(() {
    Logger.root.onRecord.listen((r) => printOnFailure(r.toString()));
  });

  setUp(() async {
    fakeDialogSupport = FakeDialogSupport();
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

  group('Given skills installed to Cursor and generic', () {
    late String rootPath;
    late SkillManifest manifest;

    setUp(() async {
      await d.dir('project', [
        d.dir('.cursor', [d.dir('skills')]),
        d.dir('.agents', [d.dir('skills')]),
      ]).create();

      rootPath = d.path('project');
      manifest = const SkillManifest();

      final installer = SkillInstaller(fakeDialogSupport);
      var result = await installer.installSkillsForIde(
        ide: Ide.cursor,
        rootPath: rootPath,
        skills: [...pkgASkills, ...pkgBSkills],
        previousManifest: manifest,
        globalConfig: const GlobalConfig(),
      );
      manifest = result!.manifest;
      result = await installer.installSkillsForIde(
        ide: Ide.generic,
        rootPath: rootPath,
        skills: [...pkgASkills, ...pkgBSkills],
        previousManifest: manifest,
        globalConfig: const GlobalConfig(),
      );
      manifest = result!.manifest;
    });

    test('when removing all then both IDEs are cleaned up', () async {
      // Verify files exist before removal.
      expect(
        Directory('$rootPath/.cursor/skills/pkg_a-code-gen').existsSync(),
        isTrue,
      );
      expect(
        Directory('$rootPath/.agents/skills/pkg_a-code-gen').existsSync(),
        isTrue,
      );

      manifest = await SkillInstaller(
        fakeDialogSupport,
      ).removeAllSkills(rootPath: rootPath, manifest: manifest);

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
        Directory('$rootPath/.agents/skills/pkg_a-code-gen').existsSync(),
        isFalse,
      );
      expect(
        Directory('$rootPath/.agents/skills/pkg_b-testing').existsSync(),
        isFalse,
      );
      expect(
        Directory('$rootPath/.agents/skills/pkg_b-debugging').existsSync(),
        isFalse,
      );

      expect(manifest.isEmpty, isTrue);
    });

    test('when removing one IDE then the other remains intact', () async {
      // Remove only Cursor.
      final result = await SkillInstaller(fakeDialogSupport).removeSkillsForIde(
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

      // Generic (.agents) files still present.
      expect(
        Directory('$rootPath/.agents/skills/pkg_a-code-gen').existsSync(),
        isTrue,
      );
      expect(
        Directory('$rootPath/.agents/skills/pkg_b-testing').existsSync(),
        isTrue,
      );

      expect(manifest.allIdes, equals(['generic']));
      expect(manifest.sourceUrisForIde('generic'), hasLength(2));
    });

    test(
      'when removing one package from all IDEs then other package remains',
      () async {
        // Remove pkg_a from both IDEs.
        final installer = SkillInstaller(fakeDialogSupport);
        for (final ideName in manifest.allIdes.toList()) {
          final ide = Ide.fromCliName(ideName)!;
          final result = await installer.removeSkillsForIde(
            ide: ide,
            rootPath: rootPath,
            manifest: manifest,
            sourceUris: {'package:pkg_a'},
          );
          manifest = result.manifest;
        }

        // pkg_a skills gone from both IDEs.
        expect(
          Directory('$rootPath/.cursor/skills/pkg_a-code-gen').existsSync(),
          isFalse,
        );
        expect(
          Directory('$rootPath/.agents/skills/pkg_a-code-gen').existsSync(),
          isFalse,
        );

        // pkg_b skills still present in both IDEs.
        expect(
          Directory('$rootPath/.cursor/skills/pkg_b-testing').existsSync(),
          isTrue,
        );
        expect(
          Directory('$rootPath/.agents/skills/pkg_b-debugging').existsSync(),
          isTrue,
        );

        expect(manifest.sourceUrisForIde('cursor'), contains('package:pkg_b'));
        expect(manifest.sourceUrisForIde('generic'), contains('package:pkg_b'));
        expect(
          manifest.sourceUrisForIde('cursor'),
          isNot(contains('package:pkg_a')),
        );
      },
    );
  });

  group('Given skills installed then manually deleted from disk', () {
    late String rootPath;
    late SkillManifest manifest;

    setUp(() async {
      await d.dir('project', [
        d.dir('.cursor', [d.dir('skills')]),
        d.dir('.agents', [d.dir('skills')]),
      ]).create();

      rootPath = d.path('project');
      manifest = const SkillManifest();

      final installer = SkillInstaller(fakeDialogSupport);
      var result = await installer.installSkillsForIde(
        ide: Ide.cursor,
        rootPath: rootPath,
        skills: pkgASkills,
        previousManifest: manifest,
        globalConfig: const GlobalConfig(),
      );
      manifest = result!.manifest;
      result = await installer.installSkillsForIde(
        ide: Ide.generic,
        rootPath: rootPath,
        skills: pkgASkills,
        previousManifest: manifest,
        globalConfig: const GlobalConfig(),
      );
      manifest = result!.manifest;
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
        manifest = await SkillInstaller(
          fakeDialogSupport,
        ).removeAllSkills(rootPath: rootPath, manifest: manifest);

        expect(manifest.isEmpty, isTrue);

        // Generic (.agents) was removed normally.
        expect(
          Directory('$rootPath/.agents/skills/pkg_a-code-gen').existsSync(),
          isFalse,
        );
      },
    );

    test('when some skills are manually deleted then remaining are still '
        'removed correctly', () async {
      // Install a second package too.
      var result = await SkillInstaller(fakeDialogSupport).installSkillsForIde(
        ide: Ide.cursor,
        rootPath: rootPath,
        skills: [...pkgASkills, ...pkgBSkills],
        previousManifest: manifest,
        globalConfig: const GlobalConfig(),
      );
      manifest = result!.manifest;

      // Manually delete pkg_a skill from cursor.
      Directory(
        '$rootPath/.cursor/skills/pkg_a-code-gen',
      ).deleteSync(recursive: true);

      // Remove all.
      manifest = await SkillInstaller(
        fakeDialogSupport,
      ).removeAllSkills(rootPath: rootPath, manifest: manifest);

      // Everything should be clean, no errors.
      expect(manifest.isEmpty, isTrue);
      expect(
        Directory('$rootPath/.cursor/skills/pkg_b-testing').existsSync(),
        isFalse,
      );
    });
  });

  group('Given skills installed to Cursor and generic', () {
    late String rootPath;
    late SkillManifest manifest;

    setUp(() async {
      await d.dir('project2', [
        d.dir('.cursor', [d.dir('skills')]),
        d.dir('.agents', [d.dir('skills')]),
      ]).create();

      rootPath = d.path('project2');
      manifest = const SkillManifest();

      final installer = SkillInstaller(fakeDialogSupport);
      var result = await installer.installSkillsForIde(
        ide: Ide.cursor,
        rootPath: rootPath,
        skills: pkgASkills,
        previousManifest: manifest,
        globalConfig: const GlobalConfig(),
      );
      manifest = result!.manifest;
      result = await installer.installSkillsForIde(
        ide: Ide.generic,
        rootPath: rootPath,
        skills: pkgASkills,
        previousManifest: manifest,
        globalConfig: const GlobalConfig(),
      );
      manifest = result!.manifest;
    });

    test('when reinstalling to one IDE then the other is untouched', () async {
      // Reinstall to Cursor only (simulating `skills get --ide cursor`).
      // SkillInstaller removes existing before installing.
      final result = await SkillInstaller(fakeDialogSupport)
          .installSkillsForIde(
            ide: Ide.cursor,
            rootPath: rootPath,
            skills: pkgASkills,
            previousManifest: manifest,
            globalConfig: const GlobalConfig(),
          );
      manifest = result!.manifest;

      // Cursor reinstalled.
      expect(
        Directory('$rootPath/.cursor/skills/pkg_a-code-gen').existsSync(),
        isTrue,
      );

      // Generic (.agents) untouched.
      expect(
        Directory('$rootPath/.agents/skills/pkg_a-code-gen').existsSync(),
        isTrue,
      );

      expect(manifest.allIdes, containsAll(['cursor', 'generic']));
    });
  });

  group('Given skills installed to Cursor and Claude', () {
    late String rootPath;
    late SkillManifest manifest;

    setUp(() async {
      await d.dir('project3', [
        d.dir('.cursor', [d.dir('skills')]),
        d.dir('.claude', [d.dir('skills')]),
      ]).create();

      rootPath = d.path('project3');
      manifest = const SkillManifest();

      final installer = SkillInstaller(fakeDialogSupport);
      var result = await installer.installSkillsForIde(
        ide: Ide.cursor,
        rootPath: rootPath,
        skills: [...pkgASkills, ...pkgBSkills],
        previousManifest: manifest,
        globalConfig: const GlobalConfig(),
      );
      manifest = result!.manifest;
      result = await installer.installSkillsForIde(
        ide: Ide.claude,
        rootPath: rootPath,
        skills: [...pkgASkills, ...pkgBSkills],
        previousManifest: manifest,
        globalConfig: const GlobalConfig(),
      );
      manifest = result!.manifest;
    });

    test('when listing then manifest reports both IDEs correctly', () {
      expect(manifest.allIdes, containsAll(['cursor', 'claude']));

      expect(manifest.sourceUrisForIde('cursor'), hasLength(2));
      expect(manifest.sourceUrisForIde('claude'), hasLength(2));

      expect(manifest.allSkillsForIde('cursor'), hasLength(3));
      expect(manifest.allSkillsForIde('claude'), hasLength(3));

      expect(manifest.allSkills, hasLength(6));
    });

    test('when removing all then both Cursor and Claude skill directories '
        'are cleaned up', () async {
      // Verify skill directories exist.
      expect(
        Directory('$rootPath/.cursor/skills/pkg_a-code-gen').existsSync(),
        isTrue,
      );
      expect(
        Directory('$rootPath/.claude/skills/pkg_a-code-gen').existsSync(),
        isTrue,
      );

      manifest = await SkillInstaller(
        fakeDialogSupport,
      ).removeAllSkills(rootPath: rootPath, manifest: manifest);

      // Agent Skills directories cleaned.
      expect(
        Directory('$rootPath/.cursor/skills/pkg_a-code-gen').existsSync(),
        isFalse,
      );
      expect(
        Directory('$rootPath/.cursor/skills/pkg_b-testing').existsSync(),
        isFalse,
      );

      expect(
        Directory('$rootPath/.claude/skills/pkg_a-code-gen').existsSync(),
        isFalse,
      );
      expect(
        Directory('$rootPath/.claude/skills/pkg_b-testing').existsSync(),
        isFalse,
      );

      expect(manifest.isEmpty, isTrue);
    });
  });

  group('Given generic IDE (antigravity/codex/generic)', () {
    test(
      'when installing then manifest stores canonical name generic only',
      () async {
        await d.dir('generic_project', [
          d.dir('.agents', [d.dir('skills')]),
        ]).create();
        final rootPath = d.path('generic_project');

        var manifest = const SkillManifest();
        final result = await SkillInstaller(fakeDialogSupport)
            .installSkillsForIde(
              ide: Ide.generic,
              rootPath: rootPath,
              skills: pkgASkills,
              previousManifest: manifest,
              globalConfig: const GlobalConfig(),
            );
        manifest = result!.manifest;

        expect(manifest.allIdes, equals(['generic']));
        expect(manifest.sourceUrisForIde('generic'), hasLength(1));
        expect(
          manifest.sourceUrisForIde('generic')['package:pkg_a']!.skills,
          hasLength(1),
        );
        expect(manifest.installations.containsKey('antigravity'), isFalse);
        expect(manifest.installations.containsKey('codex'), isFalse);
      },
    );
  });

  group('Given manifest saved to and loaded from disk', () {
    test(
      'when round-tripping multi-IDE manifest then all data preserved',
      () async {
        await d.dir('persist_project').create();
        final rootPath = d.path('persist_project');

        var manifest = const SkillManifest();
        manifest = manifest.withSourceUri(
          'cursor',
          'package:pkg_a',
          SkillsEntry(
            skills: [
              InstalledSkillEntry(
                name: 'pkg_a-code-gen',
                installedAt: DateTime.utc(2026, 3, 1),
              ),
            ],
          ),
        );
        manifest = manifest.withSourceUri(
          'generic',
          'package:pkg_a',
          SkillsEntry(
            skills: [
              InstalledSkillEntry(
                name: 'pkg_a-code-gen',
                installedAt: DateTime.utc(2026, 3, 1),
              ),
            ],
          ),
        );
        manifest = manifest.withSourceUri(
          'claude',
          'package:pkg_b',
          SkillsEntry(
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

        final loaded = await SkillManifest.loadFromRoot(rootPath);
        expect(loaded, isNotNull);
        expect(
          loaded!.allIdes.toSet(),
          equals({'cursor', 'generic', 'claude'}),
        );
        expect(
          loaded.sourceUrisForIde('cursor')['package:pkg_a']!.skills,
          hasLength(1),
        );
        expect(
          loaded.sourceUrisForIde('generic')['package:pkg_a']!.skills,
          hasLength(1),
        );
        expect(
          loaded.sourceUrisForIde('claude')['package:pkg_b']!.skills,
          hasLength(1),
        );
      },
    );
  });
}
