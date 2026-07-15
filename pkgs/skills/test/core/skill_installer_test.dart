import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:skills/src/core/skill_installer.dart';
import 'package:skills/src/core/skill_scanner.dart';
import 'package:skills/src/agent/agent.dart';
import 'package:skills/src/models/global_config.dart';
import 'package:skills/src/models/skill_manifest.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import '../fake_dialog_support.dart';

void main() {
  setUpAll(() {
    Logger.root.onRecord.listen((r) => printOnFailure(r.toString()));
  });

  group('Given an existing project that needs migration', () {
    late String rootPath;
    late List<ScannedSkill> scannedSkills;
    late SkillManifest manifest;

    setUp(() async {
      // Create a project with an old .agent directory
      await d.dir('project', [
        d.dir('.agent', [
          d.dir('skills', [
            d.dir('pkg_a-skill', [d.file('SKILL.md', 'old content')]),
          ]),
        ]),
      ]).create();
      // Create a manifest that knows about the old skill
      manifest = const SkillManifest().withSourceUri(
        'generic',
        'package:pkg_a',
        SkillsEntry(
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
          d.dir('pkg_a-skill', [d.file('SKILL.md', 'Skill content')]),
        ]),
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
        agent: Agent.generic,
        rootPath: rootPath,
        skills: scannedSkills,
        previousManifest: manifest,
        globalConfig: const GlobalConfig(),
      );

      expect(result, isNotNull);

      expect(
        Directory(
          p.join(rootPath, '.agents', 'skills', 'pkg_a-skill'),
        ).existsSync(),
        isTrue,
      );
      expect(Directory(p.join(rootPath, '.agent')).existsSync(), isFalse);
    });
  });

  group('Given an orphaned skill', () {
    late String rootPath;
    late List<ScannedSkill> scannedSkills;
    late SkillManifest manifest;

    setUp(() async {
      await d.dir('project', [
        d.dir('.agents', [
          d.dir('skills', [
            d.dir('pkg_a-skill1', [d.file('SKILL.md', 'local edits')]),
          ]),
        ]),
      ]).create();

      // Manifest has skill1 and skill2, but skill1's hash differs from 'local edits'
      manifest = const SkillManifest().withSourceUri(
        'generic',
        'package:pkg_a',
        SkillsEntry(
          skills: [
            InstalledSkillEntry(
              name: 'pkg_a-skill1',
              installedAt: DateTime.utc(2026),
              contentHash: 'different_hash',
            ),
            InstalledSkillEntry(
              name: 'pkg_a-skill2',
              installedAt: DateTime.utc(2026),
              contentHash: 'hash2',
            ),
          ],
        ),
      );
      rootPath = d.path('project');

      await d.dir('pkg_a', [
        d.dir('skills', [
          d.dir('pkg_a-skill2', [d.file('SKILL.md', 'Skill2 content')]),
        ]),
      ]).create();

      // Only skill2 is still present upstream
      scannedSkills = [
        ScannedSkill(
          packageName: 'pkg_a',
          skillName: 'pkg_a-skill2',
          skillPath: p.join(d.path('pkg_a'), 'skills', 'pkg_a-skill2'),
        ),
      ];
    });

    test('when the skill is not uninstalled', () async {
      final dialogSupport = FakeDialogSupport();
      final installer = SkillInstaller(dialogSupport);
      final logs = <LogRecord>[];
      final sub = Logger.root.onRecord.listen(logs.add);
      addTearDown(sub.cancel);

      final result = await installer.installSkillsForIde(
        agent: Agent.generic,
        rootPath: rootPath,
        skills: scannedSkills,
        selectedSkills: {'pkg_a-skill2'},
        previousManifest: manifest,
        globalConfig: const GlobalConfig(),
      );

      final newManifest = result!.manifest;
      final pkgSkills = newManifest
          .sourceUrisForAgent('generic')['package:pkg_a']!
          .skills;

      expect(
        pkgSkills.map((s) => s.name),
        isNot(contains('pkg_a-skill1')),
        reason: 'then it is removed from the manifest',
      );
      expect(pkgSkills.map((s) => s.name), contains('pkg_a-skill2'));
      final printedInstallPath = p.join(
        Agent.generic.skillsRelativePath.replaceAll(p.url.separator, p.separator),
        'pkg_a-skill1',
      );
      expect(
        logs,
        contains(
          isA<LogRecord>().having(
            (r) => r.message,
            'message',
            allOf(
              contains(
                'The following skills were not uninstalled but were '
                'deleted upstream and are now orphaned',
              ),
              contains(
                '- pkg_a-skill1 (installed at '
                '$printedInstallPath)',
              ),
            ),
          ),
        ),
        reason: 'then a message about the orphaned skill is logged',
      );
    });
  });
}
