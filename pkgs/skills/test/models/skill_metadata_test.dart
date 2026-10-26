import 'dart:io';

import 'package:logging/logging.dart';
import 'package:skills/src/models/skill_metadata.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  setUpAll(() {
    Logger.root.onRecord.listen((r) => printOnFailure(r.toString()));
  });

  group('Given a valid SKILL.md with name and description', () {
    test('when parsing then returns correct metadata', () async {
      final content = '''
---
name: my-pkg-my-skill
description: A test skill for doing things.
---

# My Skill

Some instructions here.
''';
      final metadata = SkillMetadata.parseContent(content);

      expect(metadata.name, equals('my-pkg-my-skill'));
      expect(metadata.description, equals('A test skill for doing things.'));
      expect(metadata.body, contains('# My Skill'));
      expect(metadata.body, contains('Some instructions here.'));
    });

    test('when parsing then extra fields are preserved', () async {
      final content = '''
---
name: my-pkg-my-skill
description: A test skill.
license: Apache-2.0
---

Body content.
''';
      final metadata = SkillMetadata.parseContent(content);

      expect(metadata.extraFields, containsPair('license', 'Apache-2.0'));
    });
  });

  group('Given a SKILL.md file on disk', () {
    test('when parsing from file then returns correct metadata', () async {
      await d.dir('test-pkg-test-skill', [
        d.file('SKILL.md', '''
---
name: test-pkg-test-skill
description: A file-based test skill.
---

# Test Skill

Instructions.
'''),
      ]).create();

      final skillFile = File(d.path('test-pkg-test-skill/SKILL.md'));
      final metadata = await SkillMetadata.parse(skillFile);

      expect(metadata.name, equals('test-pkg-test-skill'));
      expect(metadata.description, equals('A file-based test skill.'));
    });
  });

  group('Given an invalid SKILL.md', () {
    test('when missing frontmatter then throws FormatException', () {
      expect(
        () => SkillMetadata.parseContent('# No frontmatter'),
        throwsA(isA<FormatException>()),
      );
    });

    test('when missing closing --- then throws FormatException', () {
      expect(
        () => SkillMetadata.parseContent('---\nname: x\n'),
        throwsA(isA<FormatException>()),
      );
    });

    test('when missing name field then throws FormatException', () {
      expect(
        () =>
            SkillMetadata.parseContent('---\ndescription: no name\n---\nbody'),
        throwsA(isA<FormatException>()),
      );
    });

    test('when missing description field then throws FormatException', () {
      expect(
        () => SkillMetadata.parseContent('---\nname: my-skill\n---\nbody'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('Given a SkillMetadata instance', () {
    test('when serializing to SKILL.md then round-trips correctly', () {
      final original = SkillMetadata(
        name: 'pkg-round-trip',
        description: 'Testing round trip.',
        body: '# Round Trip\n\nInstructions here.\n',
        extraFields: {'license': 'MIT'},
      );

      final serialized = original.toSkillMd();
      final parsed = SkillMetadata.parseContent(serialized);

      expect(parsed.name, equals(original.name));
      expect(parsed.description, equals(original.description));
      expect(parsed.body, contains('# Round Trip'));
      expect(parsed.extraFields, containsPair('license', 'MIT'));
    });
  });
}
