import 'dart:io';

import 'package:logging/logging.dart';
import 'package:skills/src/models/skill_manifest.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  setUpAll(() {
    Logger.root.onRecord.listen((r) => printOnFailure(r.toString()));
  });

  group('Given a project with installed skills in multiple IDEs', () {
    late SkillManifest manifest;

    setUp(() async {
      manifest = SkillManifest(
        installations: {
          'cursor': {
            'pkg_a': PackageSkillsEntry(
              skills: [
                InstalledSkillEntry(
                  name: 'pkg_a-code-gen',
                  installedAt: DateTime.utc(2026, 2, 25),
                ),
                InstalledSkillEntry(
                  name: 'pkg_a-api-helper',
                  installedAt: DateTime.utc(2026, 2, 25),
                ),
              ],
            ),
            'pkg_b': PackageSkillsEntry(
              skills: [
                InstalledSkillEntry(
                  name: 'pkg_b-testing',
                  installedAt: DateTime.utc(2026, 2, 25),
                ),
              ],
            ),
          },
          'claude': {
            'pkg_a': PackageSkillsEntry(
              skills: [
                InstalledSkillEntry(
                  name: 'pkg_a-code-gen',
                  installedAt: DateTime.utc(2026, 2, 25),
                ),
              ],
            ),
          },
        },
      );

      await d.dir('project').create();
      await manifest.save(File(SkillManifest.pathIn(d.path('project'))));
    });

    test('when listing then all IDEs and packages are present', () {
      expect(manifest.allIdes, containsAll(['cursor', 'claude']));
      expect(manifest.packagesForIde('cursor'), hasLength(2));
      expect(manifest.packagesForIde('claude'), hasLength(1));
    });

    test('when listing then cursor skills are correct', () {
      final cursorPkgA = manifest.packagesForIde('cursor')['pkg_a']!.skills;
      expect(
        cursorPkgA.map((s) => s.name),
        containsAll(['pkg_a-code-gen', 'pkg_a-api-helper']),
      );
    });

    test('when listing then claude skills are correct', () {
      final claudePkgA = manifest.packagesForIde('claude')['pkg_a']!.skills;
      expect(claudePkgA.map((s) => s.name), equals(['pkg_a-code-gen']));
    });

    test('when iterating allSkills then returns total across IDEs', () {
      expect(manifest.allSkills, hasLength(4));
    });

    test('when iterating allSkillsForIde then returns only that IDE', () {
      expect(manifest.allSkillsForIde('cursor'), hasLength(3));
      expect(manifest.allSkillsForIde('claude'), hasLength(1));
    });
  });

  group('Given a project with no installed skills', () {
    test('when loading manifest then returns null', () async {
      await d.dir('bare_project').create();

      final manifest = await SkillManifest.loadFromRoot(d.path('bare_project'));

      expect(manifest, isNull);
    });

    test('when creating empty manifest then isEmpty is true', () {
      const manifest = SkillManifest();

      expect(manifest.isEmpty, isTrue);
      expect(manifest.allSkills, isEmpty);
      expect(manifest.allIdes, isEmpty);
    });
  });
}
