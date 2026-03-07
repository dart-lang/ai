import 'package:skills/src/core/skill_merger.dart';
import 'package:skills/src/core/skill_scanner.dart';
import 'package:test/test.dart';

void main() {
  group('mergeSkills', () {
    test(
      'when package has both dart and registry skills then only dart included',
      () {
        final dartSkills = [
          ScannedSkill(
            packageName: 'pkg_a',
            skillName: 'pkg_a-dart-skill',
            skillPath: '/dart/pkg_a/skills/pkg_a-dart-skill',
          ),
        ];
        final registrySkills = [
          ScannedSkill(
            packageName: 'pkg_a',
            skillName: 'pkg_a-registry-skill',
            skillPath: '/repos/owner/repo/skills/pkg_a-registry-skill',
          ),
        ];
        final resolved = {'pkg_a'};

        final result = mergeSkills(
          dartSkills: dartSkills,
          registrySkills: registrySkills,
          resolvedPackageNames: resolved,
        );

        expect(result, hasLength(1));
        expect(result.single.skillName, equals('pkg_a-dart-skill'));
      },
    );

    test(
      'when package only in registry and in deps then registry included',
      () {
        final dartSkills = <ScannedSkill>[];
        final registrySkills = [
          ScannedSkill(
            packageName: 'pkg_b',
            skillName: 'pkg_b-buttons',
            skillPath: '/repos/flutter/skills/skills/pkg_b-buttons',
          ),
        ];
        final resolved = {'pkg_b'};

        final result = mergeSkills(
          dartSkills: dartSkills,
          registrySkills: registrySkills,
          resolvedPackageNames: resolved,
        );

        expect(result, hasLength(1));
        expect(result.single.skillName, equals('pkg_b-buttons'));
      },
    );

    test('when package only in registry but not in deps then excluded', () {
      final dartSkills = <ScannedSkill>[];
      final registrySkills = [
        ScannedSkill(
          packageName: 'other_pkg',
          skillName: 'other_pkg-foo',
          skillPath: '/repos/skills/other_pkg-foo',
        ),
      ];
      final resolved = {'pkg_a'}; // only pkg_a is a dependency

      final result = mergeSkills(
        dartSkills: dartSkills,
        registrySkills: registrySkills,
        resolvedPackageNames: resolved,
      );

      expect(result, isEmpty);
    });

    test('when mixed then dart plus filtered registry', () {
      final dartSkills = [
        ScannedSkill(
          packageName: 'pkg_a',
          skillName: 'pkg_a-dart',
          skillPath: '/dart/pkg_a/skills/pkg_a-dart',
        ),
      ];
      final registrySkills = [
        ScannedSkill(
          packageName: 'pkg_a',
          skillName: 'pkg_a-registry',
          skillPath: '/repos/skills/pkg_a-registry',
        ),
        ScannedSkill(
          packageName: 'pkg_b',
          skillName: 'pkg_b-registry',
          skillPath: '/repos/skills/pkg_b-registry',
        ),
      ];
      final resolved = {'pkg_a', 'pkg_b'};

      final result = mergeSkills(
        dartSkills: dartSkills,
        registrySkills: registrySkills,
        resolvedPackageNames: resolved,
      );

      expect(result, hasLength(2));
      expect(
        result.map((s) => s.skillName).toSet(),
        equals({'pkg_a-dart', 'pkg_b-registry'}),
      );
    });
  });
}
