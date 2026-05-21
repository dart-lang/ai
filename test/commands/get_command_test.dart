import 'dart:io';

import 'package:skills/src/core/skill_scanner.dart';
import 'package:skills/src/ide/adapters/cursor_adapter.dart';
import 'package:skills/src/models/skill_manifest.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  group('Given a project with dependencies containing pre-prefixed skills', () {
    late String projectPath;

    setUp(() async {
      await d.dir('dep_with_skills', [
        d.dir('lib', [d.file('dep.dart', '')]),
        d.dir('skills', [
          d.dir('dep_with_skills-code-gen', [
            d.file('SKILL.md', '''
---
name: dep_with_skills-code-gen
description: Generates code from templates.
---

# Code Generator

Use this to generate boilerplate code.
'''),
          ]),
          d.dir('dep_with_skills-api-helper', [
            d.file('SKILL.md', '''
---
name: dep_with_skills-api-helper
description: Helps design APIs.
---

# API Helper

API design guidelines.
'''),
          ]),
        ]),
      ]).create();

      await d.dir('project', [
        d.dir('.cursor', [d.dir('skills')]),
      ]).create();

      projectPath = d.path('project');
    });

    test(
      'when installing skills then copies them to .cursor/skills/',
      () async {
        final adapter = CursorAdapter(projectPath);
        await adapter.ensureSkillsDirectory();

        final skills = [
          ScannedSkill(
            packageName: 'dep_with_skills',
            skillName: 'dep_with_skills-code-gen',
            skillPath: d.path(
              'dep_with_skills/skills/dep_with_skills-code-gen',
            ),
          ),
          ScannedSkill(
            packageName: 'dep_with_skills',
            skillName: 'dep_with_skills-api-helper',
            skillPath: d.path(
              'dep_with_skills/skills/dep_with_skills-api-helper',
            ),
          ),
        ];

        final installedEntries = <InstalledSkillEntry>[];
        for (final skill in skills) {
          final name = await adapter.installSkill(skill);
          installedEntries.add(
            InstalledSkillEntry(
              name: name,
              installedAt: DateTime.now().toUtc(),
            ),
          );
        }

        expect(installedEntries, hasLength(2));

        final dir1 = Directory(
          '$projectPath/.cursor/skills/dep_with_skills-code-gen',
        );
        expect(await dir1.exists(), isTrue);

        final dir2 = Directory(
          '$projectPath/.cursor/skills/dep_with_skills-api-helper',
        );
        expect(await dir2.exists(), isTrue);
      },
    );

    test(
      'when installing skills then manifest is populated correctly',
      () async {
        final adapter = CursorAdapter(projectPath);
        await adapter.ensureSkillsDirectory();

        final skill = ScannedSkill(
          packageName: 'dep_with_skills',
          skillName: 'dep_with_skills-code-gen',
          skillPath: d.path('dep_with_skills/skills/dep_with_skills-code-gen'),
        );

        final installedName = await adapter.installSkill(skill);

        var manifest = const SkillManifest();
        manifest = manifest.withPackage(
          'cursor',
          'dep_with_skills',
          PackageSkillsEntry(
            skills: [
              InstalledSkillEntry(
                name: installedName,
                installedAt: DateTime.now().toUtc(),
              ),
            ],
          ),
        );

        final manifestFile = File(SkillManifest.pathIn(projectPath));
        await manifest.save(manifestFile);

        final loaded = await SkillManifest.loadFromRoot(projectPath);
        expect(loaded, isNotNull);
        expect(
          loaded!
              .packagesForIde('cursor')['dep_with_skills']!
              .skills
              .first
              .name,
          equals('dep_with_skills-code-gen'),
        );
      },
    );
  });

  group('Given skills already installed for a package', () {
    test('when reinstalling then old skills are replaced', () async {
      await d.dir('project', [
        d.dir('.cursor', [
          d.dir('skills', [
            d.dir('old_pkg-old-skill', [
              d.file(
                'SKILL.md',
                '---\nname: old_pkg-old-skill\ndescription: old\n---\nOld',
              ),
            ]),
          ]),
        ]),
      ]).create();

      await d.dir('old_pkg_source', [
        d.dir('skills', [
          d.dir('old_pkg-new-skill', [
            d.file('SKILL.md', '''
---
name: old_pkg-new-skill
description: Replacement.
---

New skill body.
'''),
          ]),
        ]),
      ]).create();

      final adapter = CursorAdapter(d.path('project'));

      await adapter.removeSkill('old_pkg-old-skill');
      expect(
        await Directory(
          d.path('project/.cursor/skills/old_pkg-old-skill'),
        ).exists(),
        isFalse,
      );

      final skill = ScannedSkill(
        packageName: 'old_pkg',
        skillName: 'old_pkg-new-skill',
        skillPath: d.path('old_pkg_source/skills/old_pkg-new-skill'),
      );
      await adapter.installSkill(skill);

      expect(
        await Directory(
          d.path('project/.cursor/skills/old_pkg-new-skill'),
        ).exists(),
        isTrue,
      );
    });
  });

  group('Given multi-IDE installation', () {
    test('when installing for two IDEs then manifest tracks both', () async {
      var manifest = const SkillManifest();

      final entry = PackageSkillsEntry(
        skills: [
          InstalledSkillEntry(
            name: 'pkg-skill-a',
            installedAt: DateTime.utc(2026),
          ),
        ],
      );

      manifest = manifest.withPackage('cursor', 'pkg', entry);
      manifest = manifest.withPackage('claude', 'pkg', entry);

      expect(manifest.allIdes, containsAll(['cursor', 'claude']));
      expect(manifest.packagesForIde('cursor')['pkg']!.skills, hasLength(1));
      expect(manifest.packagesForIde('claude')['pkg']!.skills, hasLength(1));
    });
  });
}
