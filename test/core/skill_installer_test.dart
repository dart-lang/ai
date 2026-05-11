import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills/src/core/skill_installer.dart';
import 'package:skills/src/core/skill_scanner.dart';
import 'package:skills/src/ide/ide.dart';
import 'package:skills/src/models/skill_manifest.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  group('Given an existing project that needs migration', () {
    late String rootPath;
    late List<ScannedSkill> scannedSkills;
    late SkillManifest manifest;

    setUp(() async {
      // Create a project with an old .agent directory
      await d.dir('project', [
        d.dir('.agent', [
          d.dir('skills', [
            d.dir('pkg_a-skill', [
              d.file('SKILL.md', 'old content'),
            ]),
          ]),
        ]),
      ]).create();
      // Create a manifest that knows about the old skill
      manifest = const SkillManifest().withPackage(
        'generic',
        'pkg_a',
        PackageSkillsEntry(
          skills: [
            InstalledSkillEntry(
              name: 'pkg_a-skill',
              installedAt: DateTime.utc(2026),
            ),
          ],
        ),
      );
      rootPath = d.path('project');

      await d.dir('pkg_a', [
        d.dir('skills', [
          d.dir('pkg_a-skill', [d.file('SKILL.md', 'Skill content')])
        ])
      ]).create();
      scannedSkills = [
        ScannedSkill(
          packageName: 'pkg_a',
          skillName: 'pkg_a-skill',
          skillPath: p.join(d.path('pkg_a'), 'skills', 'pkg_a-skill'),
        ),
      ];
    });

    test('when installing skills then migrations are performed', () async {
      final installer = SkillInstaller(null);

      final result = await installer.installSkillsForIde(
        ide: Ide.generic,
        rootPath: rootPath,
        skills: scannedSkills,
        manifest: manifest,
      );

      expect(result, isNotNull);

      expect(
          Directory(p.join(rootPath, '.agents', 'skills', 'pkg_a-skill'))
              .existsSync(),
          isTrue);
      expect(Directory(p.join(rootPath, '.agent')).existsSync(), isFalse);
    });
  });
}
