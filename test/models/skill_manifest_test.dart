import 'dart:io';

import 'package:skills/src/models/skill_manifest.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  group('Given a SkillManifest', () {
    test('when serializing and deserializing then round-trips correctly', () {
      final manifest = SkillManifest(
        installations: {
          'cursor': {
            'my_package': PackageSkillsEntry(
              skills: [
                InstalledSkillEntry(
                  name: 'my_package-code-gen',
                  installedAt: DateTime.utc(2026, 2, 25),
                ),
              ],
            ),
          },
        },
      );

      final json = manifest.toJson();
      final restored = SkillManifest.fromJson(json);

      expect(restored.allIdes, contains('cursor'));
      final pkgs = restored.packagesForIde('cursor');
      expect(pkgs, hasLength(1));
      expect(pkgs['my_package']!.skills, hasLength(1));
      expect(
        pkgs['my_package']!.skills.first.name,
        equals('my_package-code-gen'),
      );
    });
  });

  group('Given a manifest file on disk', () {
    test('when loading then parses correctly', () async {
      await d.dir(SkillManifest.configDirPath, [
        d.file(SkillManifest.configName, '''
{
  "version": 1,
  "installations": {
    "cursor": {
      "pkg_a": {
        "skills": [
          { "name": "pkg_a-skill-1", "installedAt": "2026-02-25T00:00:00.000Z" }
        ]
      }
    }
  }
}
'''),
      ]).create();

      final manifest = await SkillManifest.loadFromRoot(d.sandbox);

      expect(manifest, isNotNull);
      expect(manifest!.allIdes.toList(), equals(['cursor']));
      expect(
        manifest.packagesForIde('cursor')['pkg_a']!.skills.first.name,
        equals('pkg_a-skill-1'),
      );
    });

    test('when old .dart_skills directory exists then it is migrated',
        () async {
      final manifestContent = '''
{
  "version": 1,
  "installations": {
    "cursor": {
      "pkg_a": {
        "skills": [
          { "name": "pkg_a-skill-1", "installedAt": "2026-02-25T00:00:00.000Z" }
        ]
      }
    }
  }
}
''';
      await d.dir('.dart_skills', [
        d.file(SkillManifest.configName, manifestContent),
      ]).create();

      final manifest = await SkillManifest.loadFromRoot(d.sandbox);

      expect(manifest, isNotNull);
      expect(manifest!.allIdes.toList(), equals(['cursor']));

      await d.nothing('.dart_skills').validate();
      await d.dir(SkillManifest.configDirPath,
          [d.file(SkillManifest.configName, manifestContent)]).validate();
    });

    test('when file does not exist then returns null', () async {
      final manifest =
          await SkillManifest.loadFromRoot(d.path('nonexistent_project'));

      expect(manifest, isNull);
    });
  });

  group('Given a manifest being saved to disk', () {
    test('when saving then file contains valid JSON', () async {
      final manifest = SkillManifest(
        installations: {
          'cursor': {
            'pkg': PackageSkillsEntry(
              skills: [
                InstalledSkillEntry(
                  name: 'pkg-skill-a',
                  installedAt: DateTime.utc(2026, 1, 1),
                ),
              ],
            ),
          },
        },
      );

      final file = File(SkillManifest.pathIn(d.sandbox));
      await manifest.save(file);

      final loaded = await SkillManifest.loadFromRoot(d.sandbox);
      expect(loaded, isNotNull);
      expect(
        loaded!.packagesForIde('cursor')['pkg']!.skills.first.name,
        equals('pkg-skill-a'),
      );
    });
  });

  group('Given manifest mutation methods', () {
    final base = SkillManifest(
      installations: {
        'cursor': {
          'pkg_a': PackageSkillsEntry(
            skills: [
              InstalledSkillEntry(
                name: 'pkg_a-skill-1',
                installedAt: DateTime.utc(2026),
              ),
            ],
          ),
        },
      },
    );

    test('when adding a package to an IDE then it appears', () {
      final updated = base.withPackage(
        'cursor',
        'pkg_b',
        PackageSkillsEntry(
          skills: [
            InstalledSkillEntry(
              name: 'pkg_b-skill-2',
              installedAt: DateTime.utc(2026),
            ),
          ],
        ),
      );

      expect(updated.packagesForIde('cursor'), hasLength(2));
      expect(updated.packagesForIde('cursor'), contains('pkg_b'));
    });

    test('when adding a package to a new IDE then both IDEs exist', () {
      final updated = base.withPackage(
        'claude',
        'pkg_a',
        PackageSkillsEntry(
          skills: [
            InstalledSkillEntry(
              name: 'pkg_a-skill-1',
              installedAt: DateTime.utc(2026),
            ),
          ],
        ),
      );

      expect(updated.allIdes, containsAll(['cursor', 'claude']));
    });

    test('when removing a package from an IDE then it is gone', () {
      final updated = base.withoutPackage('cursor', 'pkg_a');

      expect(updated.packagesForIde('cursor'), isEmpty);
    });

    test('when removing an entire IDE then it is gone', () {
      final updated = base.withoutIde('cursor');

      expect(updated.allIdes, isEmpty);
    });

    test('when iterating allSkills then returns all entries across IDEs', () {
      final multi = base.withPackage(
        'claude',
        'pkg_c',
        PackageSkillsEntry(
          skills: [
            InstalledSkillEntry(
              name: 'pkg_c-s',
              installedAt: DateTime.utc(2026),
            ),
          ],
        ),
      );

      expect(multi.allSkills, hasLength(2));
    });

    test('when checking isEmpty on empty manifest then returns true', () {
      expect(const SkillManifest().isEmpty, isTrue);
    });

    test('when checking isEmpty on populated manifest then returns false', () {
      expect(base.isEmpty, isFalse);
    });
  });
}
