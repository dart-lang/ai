import 'dart:io';

import 'package:logging/logging.dart';
import 'package:skills/src/core/skill_scanner.dart';
import 'package:skills/src/ide/adapters/cursor_adapter.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  setUpAll(() {
    Logger.root.onRecord.listen((r) => printOnFailure(r.toString()));
  });

  group('Given a CursorAdapter', () {
    late CursorAdapter adapter;

    setUp(() async {
      await d.dir('project', [
        d.dir('.cursor', [d.dir('skills')]),
      ]).create();

      adapter = CursorAdapter(d.path('project'));
    });

    group('and a scanned skill with SKILL.md and supporting files', () {
      late ScannedSkill skill;

      setUp(() async {
        await d.dir('source_pkg', [
          d.dir('skills', [
            d.dir('source_pkg-my-skill', [
              d.file('SKILL.md', '''
---
name: source_pkg-my-skill
description: A test skill.
---

# My Skill

Instructions here.
'''),
              d.dir('scripts', [d.file('run.sh', '#!/bin/bash\necho hello')]),
              d.dir('references', [d.file('guide.md', '# Guide')]),
            ]),
          ]),
        ]).create();

        skill = ScannedSkill(
          packageName: 'source_pkg',
          skillName: 'source_pkg-my-skill',
          skillPath: d.path('source_pkg/skills/source_pkg-my-skill'),
        );
      });

      test('when installing then creates directory with skill name', () async {
        final name = (await adapter.installSkill(skill)).name;

        expect(name, equals('source_pkg-my-skill'));

        final installed = Directory(
          d.path('project/.cursor/skills/source_pkg-my-skill'),
        );
        expect(await installed.exists(), isTrue);
      });

      test('when installing then copies SKILL.md as-is', () async {
        await adapter.installSkill(skill);

        final skillMd = File(
          d.path('project/.cursor/skills/source_pkg-my-skill/SKILL.md'),
        );
        final content = await skillMd.readAsString();

        expect(content, contains('name: source_pkg-my-skill'));
        expect(content, contains('# My Skill'));
      });

      test('when installing then copies supporting directories', () async {
        await adapter.installSkill(skill);

        final script = File(
          d.path('project/.cursor/skills/source_pkg-my-skill/scripts/run.sh'),
        );
        expect(await script.exists(), isTrue);

        final ref = File(
          d.path(
            'project/.cursor/skills/source_pkg-my-skill/references/guide.md',
          ),
        );
        expect(await ref.exists(), isTrue);
      });

      test('when reinstalling then replaces existing skill', () async {
        await adapter.installSkill(skill);
        await adapter.installSkill(skill);

        final installed = Directory(
          d.path('project/.cursor/skills/source_pkg-my-skill'),
        );
        expect(await installed.exists(), isTrue);
      });
    });

    group('and a previously installed skill', () {
      setUp(() async {
        await d.dir('project', [
          d.dir('.cursor', [
            d.dir('skills', [
              d.dir('pkg-old-skill', [
                d.file(
                  'SKILL.md',
                  '---\nname: pkg-old-skill\n'
                      'description: old\n---\nOld.',
                ),
              ]),
            ]),
          ]),
        ]).create();
      });

      test('when removing then deletes the skill directory', () async {
        await adapter.removeSkill('pkg-old-skill');

        final removed = Directory(
          d.path('project/.cursor/skills/pkg-old-skill'),
        );
        expect(await removed.exists(), isFalse);
      });
    });
  });
}
