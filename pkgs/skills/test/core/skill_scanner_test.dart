import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:skills/src/core/package_resolver.dart';
import 'package:skills/src/core/skill_scanner.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  late Logger logger;

  setUpAll(() {
    Logger.root.onRecord.listen((r) => printOnFailure(r.toString()));
  });

  group('Given a package with correctly prefixed skills', () {
    late ResolvedPackage package;

    setUp(() async {
      logger = Logger('SkillScanner test');
      await d.dir('my_package', [
        d.dir('skills', [
          d.dir('my_package-code-gen', [
            d.file('SKILL.md', '''
---
name: my_package-code-gen
description: Generates code.
---

# Code Gen

Instructions.
'''),
          ]),
          d.dir('my_package-api-design', [
            d.file('SKILL.md', '''
---
name: my_package-api-design
description: Designs APIs.
---

# API Design

Instructions.
'''),
          ]),
        ]),
      ]).create();

      package = ResolvedPackage(
        name: 'my_package',
        rootPath: d.path('my_package'),
        originalPackageConfigPath: d.path(
          p.join('.dart_tool', 'package_config.json'),
        ),
      );
    });

    test('when scanning then finds all valid skills', () async {
      final scanner = SkillScanner(logger);
      final skills = await scanner.scanPackage(package);

      expect(skills, hasLength(2));
      expect(
        skills.map((s) => s.skillName).toSet(),
        equals({'my_package-code-gen', 'my_package-api-design'}),
      );
    });

    test('when scanning then skill paths point to skill directories', () async {
      final scanner = SkillScanner(logger);
      final skills = await scanner.scanPackage(package);

      for (final skill in skills) {
        expect(skill.skillPath, contains(p.join('my_package', 'skills')));
        expect(skill.packageName, equals('my_package'));
      }
    });
  });

  group(
    'Given a package with a skill that does not match the package prefix',
    () {
      test('when scanning then the misnamed skill is skipped', () async {
        await d.dir('my_package', [
          d.dir('skills', [
            d.dir('my_package-valid', [
              d.file('SKILL.md', '''
---
name: my_package-valid
description: Valid.
---
Body.
'''),
            ]),
            d.dir('wrong-prefix-skill', [
              d.file('SKILL.md', '''
---
name: wrong-prefix-skill
description: Invalid.
---
Body.
'''),
            ]),
          ]),
        ]).create();

        final package = ResolvedPackage(
          name: 'my_package',
          rootPath: d.path('my_package'),
          originalPackageConfigPath: d.path(
            p.join('.dart_tool', 'package_config.json'),
          ),
        );

        final scanner = SkillScanner(logger);
        final skills = await scanner.scanPackage(package);

        expect(skills, hasLength(1));
        expect(skills.first.skillName, equals('my_package-valid'));
      });
    },
  );

  group('Given a package without a skills directory', () {
    test('when scanning then returns empty list', () async {
      await d.dir('no_skills_package', [
        d.dir('lib', [d.file('main.dart', 'void main() {}')]),
      ]).create();

      final package = ResolvedPackage(
        name: 'no_skills_package',
        rootPath: d.path('no_skills_package'),
        originalPackageConfigPath: d.path(
          p.join('.dart_tool', 'package_config.json'),
        ),
      );

      final scanner = SkillScanner(logger);
      final skills = await scanner.scanPackage(package);

      expect(skills, isEmpty);
    });
  });

  group('Given a package with a skills directory but no SKILL.md files', () {
    test('when scanning then returns empty list', () async {
      await d.dir('empty_skills', [
        d.dir('skills', [
          d.dir('empty_skills-not-a-skill', [
            d.file('README.md', 'not a skill'),
          ]),
        ]),
      ]).create();

      final package = ResolvedPackage(
        name: 'empty_skills',
        rootPath: d.path('empty_skills'),
        originalPackageConfigPath: d.path(
          p.join('.dart_tool', 'package_config.json'),
        ),
      );

      final scanner = SkillScanner(logger);
      final skills = await scanner.scanPackage(package);

      expect(skills, isEmpty);
    });
  });

  group('Given multiple packages', () {
    test('when scanning all then aggregates skills from each', () async {
      await d.dir('pkg_a', [
        d.dir('skills', [
          d.dir('pkg_a-skill-a', [
            d.file('SKILL.md', '''
---
name: pkg_a-skill-a
description: Skill A.
---
Body A.
'''),
          ]),
        ]),
      ]).create();

      await d.dir('pkg_b', [
        d.dir('skills', [
          d.dir('pkg_b-skill-b', [
            d.file('SKILL.md', '''
---
name: pkg_b-skill-b
description: Skill B.
---
Body B.
'''),
          ]),
        ]),
      ]).create();

      final packages = [
        ResolvedPackage(
          name: 'pkg_a',
          rootPath: d.path('pkg_a'),
          originalPackageConfigPath: d.path(
            p.join('.dart_tool', 'package_config.json'),
          ),
        ),
        ResolvedPackage(
          name: 'pkg_b',
          rootPath: d.path('pkg_b'),
          originalPackageConfigPath: d.path(
            p.join('.dart_tool', 'package_config.json'),
          ),
        ),
      ];

      final scanner = SkillScanner(logger);
      final skills = await scanner.scan(packages);

      expect(skills, hasLength(2));
      expect(
        skills.map((s) => s.packageName).toSet(),
        equals({'pkg_a', 'pkg_b'}),
      );
    });
  });
}
