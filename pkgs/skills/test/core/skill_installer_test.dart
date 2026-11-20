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

      final result = await installer.installSkillsForAgent(
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

      final result = await installer.installSkillsForAgent(
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
        Agent.generic.skillsRelativePath.replaceAll(
          p.url.separator,
          p.separator,
        ),
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

  group('Given a skill installed from both a package and a git repo', () {
    const gitUrl = 'https://github.com/owner/pkg_a.git';
    late SkillManifest manifest;
    late ScannedSkill entrySkill;

    setUp(() async {
      await d.dir('project', [
        d.dir('.agents', [
          d.dir('skills', [
            d.dir('pkg_a-skill', [d.file('SKILL.md', 'git content')]),
            d.dir('pkg_a', [d.file('SKILL.md', 'entry content')]),
          ]),
        ]),
      ]).create();
      await d.dir('repo', [
        d.dir('pkg_a', [d.file('SKILL.md', 'entry content')]),
      ]).create();

      InstalledSkillEntry installed(String name) =>
          InstalledSkillEntry(name: name, installedAt: DateTime.utc(2026));
      manifest = const SkillManifest()
          .withSourceUri(
            'generic',
            'package:pkg_a',
            SkillsEntry(skills: [installed('pkg_a-skill')]),
          )
          .withSourceUri(
            'generic',
            gitUrl,
            SkillsEntry(skills: [installed('pkg_a-skill'), installed('pkg_a')]),
          );
      entrySkill = ScannedSkill(
        gitUrl: gitUrl,
        skillName: 'pkg_a',
        skillPath: p.join(d.path('repo'), 'pkg_a'),
      );
    });

    Future<SkillManifest> install(
      List<ScannedSkill> skills, {
      Set<String> sourceUris = const {},
      Map<String, Set<String>> heldSkills = const {},
    }) async {
      final result = await SkillInstaller(null).installSkillsForAgent(
        agent: Agent.generic,
        rootPath: d.path('project'),
        skills: skills,
        previousManifest: manifest,
        globalConfig: const GlobalConfig(),
        sourceUris: sourceUris,
        heldSkills: heldSkills,
      );
      return result!.manifest;
    }

    String installedContent() => File(
      p.join(d.path('project'), '.agents', 'skills', 'pkg_a-skill', 'SKILL.md'),
    ).readAsStringSync();

    List<String> skillNames(SkillManifest manifest, String sourceUri) => [
      for (final skill
          in manifest.sourceUrisForAgent('generic')[sourceUri]?.skills ??
              const <InstalledSkillEntry>[])
        skill.name,
    ];

    test('when only the git repo is updated and it stops shipping it then the '
        'directory stays', () async {
      final newManifest = await install([entrySkill], sourceUris: {gitUrl});

      expect(installedContent(), 'git content');
      expect(skillNames(newManifest, gitUrl), ['pkg_a']);
    });

    test('when only the git repo is updated and it no longer ships any skill '
        'then the directory stays', () async {
      final newManifest = await install([], sourceUris: {gitUrl});

      expect(installedContent(), 'git content');
      expect(newManifest.sourceUrisForAgent('generic').keys, ['package:pkg_a']);
    });

    test('when both copies are held then the installer leaves them as they '
        'are', () async {
      manifest = manifest.withoutSourceUri('generic', 'package:pkg_a');
      await d.dir('repo', [
        d.dir('pkg_a-skill', [d.file('SKILL.md', 'new git content')]),
      ]).create();
      final gitSkill = ScannedSkill(
        gitUrl: gitUrl,
        skillName: 'pkg_a-skill',
        skillPath: p.join(d.path('repo'), 'pkg_a-skill'),
      );
      const packageSkill = ScannedSkill(
        packageName: 'pkg_a',
        skillName: 'pkg_a-skill',
        skillPath: 'unused',
      );

      final newManifest = await install(
        [packageSkill, gitSkill, entrySkill],
        heldSkills: {
          'package:pkg_a': {'pkg_a-skill'},
          gitUrl: {'pkg_a-skill'},
        },
      );

      expect(installedContent(), 'git content');
      expect(skillNames(newManifest, 'package:pkg_a'), isEmpty);
      expect(skillNames(newManifest, gitUrl), ['pkg_a-skill', 'pkg_a']);
    });
  });
}
