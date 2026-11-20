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
}
