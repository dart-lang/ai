import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills/src/core/skill_scanner.dart';
import 'package:skills/src/ide/adapters/claude_adapter.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  group('Given a ClaudeAdapter', () {
    late ClaudeAdapter adapter;

    setUp(() async {
      await d.dir('project', [
        d.dir('.claude', [d.dir('skills')]),
      ]).create();

      adapter = ClaudeAdapter(d.path('project'));
    });

    group('and a scanned skill without user-invocable', () {
      late ScannedSkill skill;

      setUp(() async {
        await d.dir('claude_pkg', [
          d.dir('skills', [
            d.dir('claude_pkg-code-review', [
              d.file('SKILL.md', '''
---
name: claude_pkg-code-review
description: Reviews code.
---

# Code Review

Review guidelines here.
'''),
            ]),
          ]),
        ]).create();

        skill = ScannedSkill(
          packageName: 'claude_pkg',
          skillName: 'claude_pkg-code-review',
          skillPath: d.path('claude_pkg/skills/claude_pkg-code-review'),
        );
      });

      test(
        'when installing then creates skill directory in .claude/skills/',
        () async {
          final name = await adapter.installSkill(skill);

          expect(name, equals('claude_pkg-code-review'));

          final installed = Directory(
            p.join(
              d.path('project'),
              '.claude',
              'skills',
              'claude_pkg-code-review',
            ),
          );
          expect(await installed.exists(), isTrue);
        },
      );

      test('when installing then SKILL.md is copied with user-invocable: false',
          () async {
        await adapter.installSkill(skill);

        final content = await File(
          p.join(
            d.path('project'),
            '.claude',
            'skills',
            'claude_pkg-code-review',
            'SKILL.md',
          ),
        ).readAsString();

        expect(content, '''
---
name: claude_pkg-code-review
description: Reviews code.
user-invocable: false
---

# Code Review

Review guidelines here.
''');
      });
    });

    group('and a scanned skill with user-invocable set to true', () {
      late ScannedSkill skill;
      const skillMd = '''
---
name: claude_pkg_true-review
description: Reviews code.
user-invocable: true
---

# Code Review
''';

      setUp(() async {
        await d.dir('claude_pkg_true', [
          d.dir('skills', [
            d.dir('claude_pkg_true-review', [
              d.file('SKILL.md', skillMd),
            ]),
          ]),
        ]).create();

        skill = ScannedSkill(
          packageName: 'claude_pkg_true',
          skillName: 'claude_pkg_true-review',
          skillPath: d.path('claude_pkg_true/skills/claude_pkg_true-review'),
        );
      });

      test('when installing then SKILL.md is copied with no changes', () async {
        await adapter.installSkill(skill);

        final content = await File(
          p.join(
            d.path('project'),
            '.claude',
            'skills',
            'claude_pkg_true-review',
            'SKILL.md',
          ),
        ).readAsString();

        expect(content, equals(skillMd));
      });
    });

    group('and a scanned skill with user-invocable set to false', () {
      late ScannedSkill skill;
      const skillMd = '''
---
name: claude_pkg_true-review
description: Reviews code.
user-invocable: false
---

# Code Review
''';

      setUp(() async {
        await d.dir('claude_pkg_true', [
          d.dir('skills', [
            d.dir('claude_pkg_true-review', [
              d.file('SKILL.md', skillMd),
            ]),
          ]),
        ]).create();

        skill = ScannedSkill(
          packageName: 'claude_pkg_true',
          skillName: 'claude_pkg_true-review',
          skillPath: d.path('claude_pkg_true/skills/claude_pkg_true-review'),
        );
      });

      test('when installing then SKILL.md is copied with no changes', () async {
        await adapter.installSkill(skill);

        final content = await File(
          p.join(
            d.path('project'),
            '.claude',
            'skills',
            'claude_pkg_true-review',
            'SKILL.md',
          ),
        ).readAsString();

        expect(content, equals(skillMd));
      });
    });

    group('and a scanned skill with no user-invocable and nested frontmatter',
        () {
      late ScannedSkill skill;
      const skillMd = '''
---
name: claude_pkg_nested-deploy
description: Deploys stuff.
metadata:
  version: 2
  tags:
    - deploy
    - ci
---

# Deploy
''';

      setUp(() async {
        await d.dir('claude_pkg_nested', [
          d.dir('skills', [
            d.dir('claude_pkg_nested-deploy', [
              d.file('SKILL.md', skillMd),
            ]),
          ]),
        ]).create();

        skill = ScannedSkill(
          packageName: 'claude_pkg_nested',
          skillName: 'claude_pkg_nested-deploy',
          skillPath:
              d.path('claude_pkg_nested/skills/claude_pkg_nested-deploy'),
        );
      });

      test(
        'when installing then SKILL.md is copied with user-invocable: false and preserves nested frontmatter fields byte-for-byte',
        () async {
          await adapter.installSkill(skill);

          final content = await File(
            p.join(
              d.path('project'),
              '.claude',
              'skills',
              'claude_pkg_nested-deploy',
              'SKILL.md',
            ),
          ).readAsString();

          expect(content, '''
---
name: claude_pkg_nested-deploy
description: Deploys stuff.
metadata:
  version: 2
  tags:
    - deploy
    - ci
user-invocable: false
---

# Deploy
''');
        },
      );
    });

    group('and a scanned skill with no user-invocable and no body', () {
      late ScannedSkill skill;
      const skillMd = '''
---
name: claude_pkg_nobody-empty
description: Empty body skill.
---''';

      setUp(() async {
        await d.dir('claude_pkg_nobody', [
          d.dir('skills', [
            d.dir('claude_pkg_nobody-empty', [
              d.file('SKILL.md', skillMd),
            ]),
          ]),
        ]).create();

        skill = ScannedSkill(
          packageName: 'claude_pkg_nobody',
          skillName: 'claude_pkg_nobody-empty',
          skillPath: d.path('claude_pkg_nobody/skills/claude_pkg_nobody-empty'),
        );
      });

      test(
        'when installing then SKILL.md is copied with user-invocable: false and no body',
        () async {
          await adapter.installSkill(skill);

          final content = await File(
            p.join(
              d.path('project'),
              '.claude',
              'skills',
              'claude_pkg_nobody-empty',
              'SKILL.md',
            ),
          ).readAsString();

          expect(content, '''
---
name: claude_pkg_nobody-empty
description: Empty body skill.
user-invocable: false
---''');
        },
      );
    });

    test('when removing then deletes the skill directory', () async {
      await d.dir('project', [
        d.dir('.claude', [
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

      adapter = ClaudeAdapter(d.path('project'));
      await adapter.removeSkill('pkg-skill');

      expect(
        await Directory(
          p.join(d.path('project'), '.claude', 'skills', 'pkg-skill'),
        ).exists(),
        isFalse,
      );
    });
  });
}
