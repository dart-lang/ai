// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:skills/src/core/frontmatter.dart';
import 'package:test/test.dart';

void main() {
  group('SkillFrontmatter.fromSkillContent', () {
    test('parses the name and metadata', () {
      final frontmatter = SkillFrontmatter.fromSkillContent('''
---
name: my_package-skill
description: Does things.
metadata:
  internal: true
---

# Skill
''');
      expect(frontmatter.name, 'my_package-skill');
      expect(frontmatter.isInternal, isTrue);
    });

    test('ignores --- inside a frontmatter value', () {
      final frontmatter = SkillFrontmatter.fromSkillContent('''
---
name: my_package-skill
description: Use this for builds --- not for tests.
metadata:
  internal: true
---

# Skill
''');
      expect(frontmatter.name, 'my_package-skill');
      expect(frontmatter.isInternal, isTrue);
    });

    test('ends the frontmatter at a --- line with trailing whitespace', () {
      final frontmatter = SkillFrontmatter.fromSkillContent(
        '---\nname: my_package-skill\n---  \n\n# Skill\n',
      );
      expect(frontmatter.name, 'my_package-skill');
    });

    test('parses a file with Windows line endings', () {
      final frontmatter = SkillFrontmatter.fromSkillContent(
        '---\r\nname: my_package-skill\r\nmetadata:\r\n  internal: true\r\n'
        '---\r\n\r\n# Skill\r\n',
      );
      expect(frontmatter.name, 'my_package-skill');
      expect(frontmatter.isInternal, isTrue);
    });

    test('throws when the content does not start with ---', () {
      expect(
        () => SkillFrontmatter.fromSkillContent('name: my_package-skill\n'),
        throwsFormatException,
      );
    });

    test('throws when the closing --- is missing', () {
      expect(
        () => SkillFrontmatter.fromSkillContent(
          '---\nname: my_package-skill\ndescription: a --- b\n',
        ),
        throwsFormatException,
      );
    });
  });

  group('Given metadata.install-from', () {
    Set<InstallSource> installFrom(String metadata) =>
        SkillFrontmatter.fromSkillContent(
          '---\nname: my_package-skill\n$metadata---\n',
        ).installFrom;

    test('when it is absent then git and packages may install the skill', () {
      expect(installFrom(''), InstallSource.values.toSet());
    });

    test('when it is git and package then both may install the skill', () {
      expect(installFrom('metadata:\n  install-from: git package\n'), {
        InstallSource.git,
        InstallSource.package,
      });
    });

    test('when it is package and an unknown word then only a package may '
        'install the skill', () {
      expect(installFrom('metadata:\n  install-from: package npm\n'), {
        InstallSource.package,
      });
    });

    test('when it is a block scalar then its line break is ignored', () {
      expect(installFrom('metadata:\n  install-from: >\n    package\n'), {
        InstallSource.package,
      });
    });

    test('when it is not a string then parsing throws', () {
      expect(
        () => installFrom('metadata:\n  install-from: [git, package]\n'),
        throwsFormatException,
      );
    });
  });
}
