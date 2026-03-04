import 'dart:io';

import 'package:skills/src/core/skill_scanner.dart';
import 'package:skills/src/ide/adapters/cline_adapter.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  group('Given a ClineAdapter', () {
    late ClineAdapter adapter;

    setUp(() async {
      await d.dir('project', [d.dir('.clinerules')]).create();

      adapter = ClineAdapter(d.path('project'));
    });

    group('and a scanned skill', () {
      late ScannedSkill skill;

      setUp(() async {
        await d.dir('cline_pkg', [
          d.dir('skills', [
            d.dir('cline_pkg-debugging', [
              d.file('SKILL.md', '''
---
name: cline_pkg-debugging
description: Debugging techniques.
---

# Debugging

Debugging steps.
'''),
            ]),
          ]),
        ]).create();

        skill = ScannedSkill(
          packageName: 'cline_pkg',
          skillName: 'cline_pkg-debugging',
          skillPath: d.path('cline_pkg/skills/cline_pkg-debugging'),
        );
      });

      test('when installing then creates .md file in .clinerules/', () async {
        await adapter.installSkill(skill);

        final ruleFile = File(
          d.path('project/.clinerules/cline_pkg-debugging.md'),
        );
        expect(await ruleFile.exists(), isTrue);
      });

      test(
        'when installing then file contains managed header and body',
        () async {
          await adapter.installSkill(skill);

          final content = await File(
            d.path('project/.clinerules/cline_pkg-debugging.md'),
          ).readAsString();

          expect(content, contains('<!-- managed by skills CLI -->'));
          expect(content, contains('# Debugging'));
          expect(content, contains('Debugging steps.'));
        },
      );
    });

    test('when removing then deletes the rule file', () async {
      final target = File(d.path('project/.clinerules/pkg-skill.md'));
      await target.create(recursive: true);
      await target.writeAsString('content');

      adapter = ClineAdapter(d.path('project'));
      await adapter.removeSkill('pkg-skill');

      expect(await target.exists(), isFalse);
    });
  });
}
