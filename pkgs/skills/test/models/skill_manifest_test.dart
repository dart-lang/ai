import 'dart:io';

import 'package:logging/logging.dart';
import 'package:skills/src/models/skill_manifest.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  setUpAll(() {
    Logger.root.onRecord.listen((r) => printOnFailure(r.toString()));
  });

  group('Given a SkillManifest', () {
    test('when serializing and deserializing then round-trips correctly', () {
      final manifest = SkillManifest(
        installations: {
          'cursor': {
            'package:my_package': SkillsEntry(
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

      expect(restored.allAgents, contains('cursor'));
      final pkgs = restored.sourceUrisForAgent('cursor');
      expect(pkgs, hasLength(1));
      expect(pkgs['package:my_package']!.skills, hasLength(1));
      expect(
        pkgs['package:my_package']!.skills.first.name,
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
      expect(manifest!.allAgents.toList(), equals(['cursor']));
      expect(
        manifest.sourceUrisForAgent('cursor')['pkg_a']!.skills.first.name,
        equals('pkg_a-skill-1'),
      );
    });

    test(
      'when old .dart_skills directory exists then it is migrated',
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
        expect(manifest!.allAgents.toList(), equals(['cursor']));

        await d.nothing('.dart_skills').validate();
        await d.dir(SkillManifest.configDirPath, [
          d.file(SkillManifest.configName, manifestContent),
        ]).validate();
      },
    );

    test('when file does not exist then returns null', () async {
      final manifest = await SkillManifest.loadFromRoot(
        d.path('nonexistent_project'),
      );

      expect(manifest, isNull);
    });
  });

  group('Given a manifest being saved to disk', () {
    test('when saving then file contains valid JSON', () async {
      final manifest = SkillManifest(
        installations: {
          'cursor': {
            'package:pkg': SkillsEntry(
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
        loaded!.sourceUrisForAgent('cursor')['package:pkg']!.skills.first.name,
        equals('pkg-skill-a'),
      );
    });
  });

  group('Given manifest mutation methods', () {
    final base = SkillManifest(
      installations: {
        'cursor': {
          'package:pkg_a': SkillsEntry(
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

    test('when adding a package to an agent then it appears', () {
      final updated = base.withSourceUri(
        'cursor',
        'package:pkg_b',
        SkillsEntry(
          skills: [
            InstalledSkillEntry(
              name: 'pkg_b-skill-2',
              installedAt: DateTime.utc(2026),
            ),
          ],
        ),
      );

      expect(updated.sourceUrisForAgent('cursor'), hasLength(2));
      expect(updated.sourceUrisForAgent('cursor'), contains('package:pkg_b'));
    });

    test('when adding a package to a new agent then both agents exist', () {
      final updated = base.withSourceUri(
        'claude',
        'package:pkg_a',
        SkillsEntry(
          skills: [
            InstalledSkillEntry(
              name: 'pkg_a-skill-1',
              installedAt: DateTime.utc(2026),
            ),
          ],
        ),
      );

      expect(updated.allAgents, containsAll(['cursor', 'claude']));
    });

    test('when removing a package from an agent then it is gone', () {
      final updated = base.withoutSourceUri('cursor', 'package:pkg_a');

      expect(updated.sourceUrisForAgent('cursor'), isEmpty);
    });

    test('when removing an entire agent then it is gone', () {
      final updated = base.withoutAgent('cursor');

      expect(updated.allAgents, isEmpty);
    });

    test('when iterating allSkills then returns all entries across agents', () {
      final multi = base.withSourceUri(
        'claude',
        'package:pkg_c',
        SkillsEntry(
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
