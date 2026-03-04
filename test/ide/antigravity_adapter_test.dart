import 'dart:io';

import 'package:skills/src/core/skill_scanner.dart';
import 'package:skills/src/ide/adapters/antigravity_adapter.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  group('Given an AntigravityAdapter', () {
    late AntigravityAdapter adapter;

    setUp(() async {
      await d.dir('project', [
        d.dir('.agent', [d.dir('skills')]),
      ]).create();

      adapter = AntigravityAdapter(d.path('project'));
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

      test('when installing then creates in .agent/skills/', () async {
        final name = await adapter.installSkill(skill);

        expect(name, equals('ag_pkg-data-analysis'));

        final installed = Directory(
          d.path('project/.agent/skills/ag_pkg-data-analysis'),
        );
        expect(await installed.exists(), isTrue);
      });

      test('when installing then SKILL.md is copied unchanged', () async {
        await adapter.installSkill(skill);

        final content = await File(
          d.path('project/.agent/skills/ag_pkg-data-analysis/SKILL.md'),
        ).readAsString();

        expect(content, contains('name: ag_pkg-data-analysis'));
        expect(content, contains('# Data Analysis'));
      });
    });

    test('when removing then deletes the skill directory', () async {
      await d.dir('project', [
        d.dir('.agent', [
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

      expect(
        await Directory(d.path('project/.agent/skills/pkg-skill')).exists(),
        isFalse,
      );
    });
  });
}
