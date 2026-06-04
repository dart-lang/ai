import 'dart:io';

import 'package:logging/logging.dart';
import 'package:skills/src/core/skill_scanner.dart';
import 'package:skills/src/ide/adapters/generic_adapter.dart';
import 'package:skills/src/models/skill_manifest.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import '../fake_dialog_support.dart';

void main() {
  setUpAll(() {
    Logger.root.onRecord.listen((r) => printOnFailure(r.toString()));
  });
  group('Given a GenericAdapter', () {
    late GenericAdapter adapter;
    late FakeDialogSupport fakeDialogSupport;

    setUp(() async {
      await d.dir('project', [
        d.dir('.agents', [d.dir('skills')]),
      ]).create();

      fakeDialogSupport = FakeDialogSupport();
      adapter = GenericAdapter(d.path('project'), fakeDialogSupport);
    });

    group('and a scanned skill', () {
      late ScannedSkill skill;

      setUp(() async {
        await d.dir('ag_pkg', [
          d.dir('skills', [
            d.dir('ag_pkg-data-analysis', [
              d.file('SKILL.md', '''
---
name: ag_pkg-data-analysis
description: Analyzes data.
---

# Data Analysis

Steps to analyze.
'''),
            ]),
          ]),
        ]).create();

        skill = ScannedSkill(
          packageName: 'ag_pkg',
          skillName: 'ag_pkg-data-analysis',
          skillPath: d.path('ag_pkg/skills/ag_pkg-data-analysis'),
        );
      });

      test('when installing then creates in .agents/skills/', () async {
        final name = await adapter.installSkill(skill);

        expect(name, equals('ag_pkg-data-analysis'));

        await d.dir('project', [
          d.dir('.agents', [
            d.dir('skills', [d.dir('ag_pkg-data-analysis')])
          ])
        ]).validate();
      });

      test('when installing then SKILL.md is copied unchanged', () async {
        await adapter.installSkill(skill);

        await d.dir('project', [
          d.dir('.agents', [
            d.dir('skills', [
              d.dir('ag_pkg-data-analysis', [
                d.file(
                  'SKILL.md',
                  allOf(
                    contains('name: ag_pkg-data-analysis'),
                    contains('# Data Analysis'),
                  ),
                ),
              ])
            ])
          ])
        ]).validate();
      });
    });

    test('when removing then deletes the skill directory', () async {
      await d.dir('project', [
        d.dir('.agents', [
          d.dir('skills', [
            d.dir('pkg-skill', [
              d.file(
                'SKILL.md',
                '---\nname: pkg-skill\n'
                    'description: x\n---\nbody',
              ),
            ]),
          ]),
        ]),
      ]).create();

      await adapter.removeSkill('pkg-skill');

      await d.dir('project', [
        d.dir('.agents', [
          d.dir('skills', [d.nothing('pkg-skill')])
        ])
      ]).validate();
    });
  });

  group(
      'Given an existing ".agent" directory with skills and a generic adapter',
      () {
    late GenericAdapter adapter;
    late SkillManifest manifest;

    setUp(() async {
      await d.dir('project_migration', [
        d.dir('.agent', [
          d.dir('skills', [
            d.dir('old-skill', [
              d.file('SKILL.md', 'content'),
            ]),
            d.dir('unregistered-skill', [
              d.file('SKILL.md', 'content'),
            ]),
          ]),
        ]),
      ]).create();

      manifest = const SkillManifest().withPackage(
        'generic',
        'pkg_a',
        PackageSkillsEntry(
          skills: [
            InstalledSkillEntry(
              name: 'old-skill',
              installedAt: DateTime.utc(2026),
            ),
          ],
        ),
      );
    });

    group('with dialog support', () {
      late FakeDialogSupport fakeDialogSupport;

      setUp(() async {
        fakeDialogSupport = FakeDialogSupport();
        adapter =
            GenericAdapter(d.path('project_migration'), fakeDialogSupport);
      });

      test(
          'when the user chooses to migrate known skills then other '
          'skills are left alone', () async {
        fakeDialogSupport.singleSelectResults.add(0);
        final migrated = await adapter.migrateSkillsDir(manifest);
        expect(migrated, isTrue);

        await d.dir('project_migration', [
          d.dir('.agent', [
            d.dir('skills', [
              d.nothing('old-skill'),
              d.dir('unregistered-skill'),
            ]),
          ]),
          d.dir('.agents', [
            d.dir('skills', [
              d.dir('old-skill'),
              d.nothing('unregistered-skill'),
            ])
          ]),
        ]).validate();
      });

      test(
          'when the user chooses to migrate all skills then all skills are '
          'moved and .agent is deleted', () async {
        fakeDialogSupport.singleSelectResults.add(1);
        final migrated = await adapter.migrateSkillsDir(manifest);
        expect(migrated, isTrue);

        await d.dir('project_migration', [
          d.nothing('.agent'),
          d.dir('.agents', [
            d.dir('skills', [
              d.dir('old-skill'),
              d.dir('unregistered-skill'),
            ])
          ]),
        ]).validate();
      });

      test(
          'when the user chooses to leave old skills in place then skills '
          'are not moved', () async {
        fakeDialogSupport.singleSelectResults.add(2);
        final migrated = await adapter.migrateSkillsDir(manifest);
        expect(migrated, isTrue);

        await d.dir('project_migration', [
          d.dir('.agent', [
            d.dir('skills', [
              d.dir('old-skill'),
              d.dir('unregistered-skill'),
            ]),
          ]),
          d.nothing('.agents'),
        ]).validate();
      });

      test('when existing .agents skills exist then they are merged', () async {
        // Add something to .agents before migration
        final newSkillDir =
            Directory(d.path('project_migration/.agents/skills/new-skill'));
        await newSkillDir.create(recursive: true);
        await File(
                d.path('project_migration/.agents/skills/new-skill/SKILL.md'))
            .writeAsString('content');

        fakeDialogSupport.singleSelectResults.add(0);
        final migrated = await adapter.migrateSkillsDir(manifest);
        expect(migrated, isTrue);
        await adapter.ensureSkillsDirectory();

        await d.dir('project_migration', [
          d.dir('.agents', [
            d.dir('skills', [
              d.dir('old-skill'),
              d.dir('new-skill'),
            ])
          ]),
          d.dir('.agent', [
            d.dir('skills', [
              d.nothing('old-skill'),
            ])
          ]),
        ]).validate();
      });

      test(
          'when migrating skills and user aborts the dialog then skills are not moved',
          () async {
        fakeDialogSupport.singleSelectResults.add(3);
        final migrated = await adapter.migrateSkillsDir(manifest);
        expect(migrated, isFalse);

        await d.dir('project_migration', [
          d.dir('.agent', [
            d.dir('skills', [
              d.dir('old-skill'),
            ])
          ]),
          d.nothing('.agents'),
        ]).validate();
      });
    });

    group('without dialog support', () {
      setUp(() async {
        adapter = GenericAdapter(d.path('project_migration'), null);
      });

      test('when migrating skills then known skills are migrated', () async {
        final migrated = await adapter.migrateSkillsDir(manifest);
        expect(migrated, isTrue);
        await adapter.ensureSkillsDirectory();

        await d.dir('project_migration', [
          d.dir('.agents', [
            d.dir('skills', [
              d.dir('old-skill'),
              d.nothing('unregistered-skill'),
            ])
          ]),
          d.dir('.agent', [
            d.dir('skills', [
              d.nothing('old-skill'),
              d.dir('unregistered-skill'),
            ])
          ]),
        ]).validate();
      });
    });
  });
}
