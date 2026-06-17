import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:skills/src/commands/get_command.dart';
import 'package:skills/src/core/git_runner.dart';
import 'package:skills/src/core/skill_scanner.dart';
import 'package:skills/src/ide/adapters/cursor_adapter.dart';
import 'package:skills/src/ide/ide.dart';
import 'package:skills/src/models/skill_manifest.dart';
import 'package:skills/src/commands/skills_command_runner.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import '../fake_dialog_support.dart';
import '../utils.dart';

void main() {
  setUpAll(() {
    Logger.root.onRecord.listen((r) => printOnFailure(r.toString()));
  });

  group('Given a project with dependencies containing pre-prefixed skills', () {
    late String projectPath;

    setUp(() async {
      await d.dir('dep_with_skills', [
        pubspec('dep_with_skills'),
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
        pubspec('project', dependencies: [.new('dep_with_skills')]),
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
          final result = await adapter.installSkill(skill);
          installedEntries.add(
            InstalledSkillEntry(
              name: result.name,
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

        final installedName = (await adapter.installSkill(skill)).name;

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

  group('GetCommand end-to-end overwrite testing', () {
    test(
      'when skill is modified locally, it prompts and skips overwrite if user says no',
      () async {
        final fakeDialogSupport = FakeDialogSupport();
        final getCommand = GetCommand(
          dialogSupport: fakeDialogSupport,
          gitRunner: GitRunner(isAvailableOverride: () async => false),
        );
        final runner = SkillsCommandRunner('skills', 'Test')
          ..addCommand(getCommand);

        await d.dir('dep_with_skills', [
          d.file(
            'pubspec.yaml',
            'name: dep_with_skills\nenvironment:\n  sdk: ^3.5.0\n',
          ),
          d.dir('lib', [d.file('dep.dart', '')]),
          d.dir('skills', [
            d.dir('dep_with_skills-test-skill', [
              d.file(
                'SKILL.md',
                '---\nname: dep_with_skills-test-skill\ndescription: Test\n---\n\nOriginal content',
              ),
            ]),
          ]),
        ]).create();

        await d.dir('project', [
          d.file('pubspec.yaml', '''
name: project
environment:
  sdk: ^3.5.0
dependencies:
  dep_with_skills:
    path: ../dep_with_skills
'''),
        ]).create();

        final projectPath = d.path('project');

        // 1. Initial installation
        await runner.run([
          'get',
          '--directory',
          projectPath,
          '--ide',
          Ide.cursor.cliName,
          '--all',
        ]);

        final skillPath = p.join(
          projectPath,
          '.cursor',
          'skills',
          'dep_with_skills-test-skill',
          'SKILL.md',
        );
        expect(await File(skillPath).exists(), isTrue);

        // 2. User manually modifies the installed skill file
        await File(skillPath).writeAsString(
          '---\nname: dep_with_skills-test-skill\ndescription: Test\n---\n\nModified content',
        );

        // 3. User updates/re-installs and says "No" to the overwrite prompt (index 1 is No)
        fakeDialogSupport.singleSelectResults.add(1);

        await runner.run([
          'get',
          '--directory',
          projectPath,
          '--ide',
          Ide.cursor.cliName,
          '--all',
        ]);

        expect(
          fakeDialogSupport.singleSelectCallCount,
          1,
          reason: 'Expected prompt to be shown during second update',
        );
        final contentAfterUpdate = await File(skillPath).readAsString();
        expect(
          contentAfterUpdate,
          contains('Modified content'),
          reason: 'Content should not be overwritten',
        );
      },
    );
  });
}
