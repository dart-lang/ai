import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:skills/src/core/registry_repos.dart';
import 'package:skills/src/core/registry_scanner.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  setUpAll(() {
    Logger.root.onRecord.listen((r) => printOnFailure(r.toString()));
  });

  group('RegistryScanner', () {
    test('when repos directory does not exist then returns empty', () async {
      await d.dir('project', []).create();
      const scanner = RegistryScanner();
      final skills = await scanner.scan(d.path('project'), isGlobal: false);
      expect(skills, isEmpty);
    });

    test(
      'when scanning flat layout then returns ScannedSkills with correct fields',
      () async {
        const registryRepo = RegistryRepo(
          cloneUrl: 'https://github.com/owner/repo.git',
        );
        await d.dir('project', [
          d.dir('.dart_tool', [
            d.dir('skills', [
              d.dir('repos', [
                d.dir(registryRepo.pathSegment, [
                  d.dir('skills', [
                    d.dir('my_pkg-buttons', [
                      d.file('SKILL.md', '---\nname: my_pkg-buttons\n---\n'),
                    ]),
                    d.dir('my_pkg-forms', [
                      d.file('SKILL.md', '---\nname: my_pkg-forms\n---\n'),
                    ]),
                  ]),
                ]),
              ]),
            ]),
          ]),
        ]).create();

        const scanner = RegistryScanner();
        final skills = await scanner.scan(
          d.path('project'),
          isGlobal: false,
          repos: [
            registryRepo,
          ],
        );

        expect(skills, hasLength(2));
        expect(
          skills.map((s) => s.skillName).toSet(),
          equals({'my_pkg-buttons', 'my_pkg-forms'}),
        );
        for (final s in skills) {
          expect(s.packageName, equals('my_pkg'));
          expect(s.skillPath, contains(p.join('skills', s.skillName)));
        }
      },
    );

    test(
      'when scanning groupedByPackage layout then returns ScannedSkills',
      () async {
        const registryRepo = RegistryRepo(
          cloneUrl: 'https://github.com/owner/repo.git',
        );
        await d.dir('project', [
          d.dir('.dart_tool', [
            d.dir('skills', [
              d.dir('repos', [
                d.dir(registryRepo.pathSegment, [
                  d.dir('skills', [
                    d.dir('riverpod', [
                      d.dir('riverpod-get-started', [
                        d.file(
                          'SKILL.md',
                          '---\nname: riverpod-get-started\n---\n',
                        ),
                      ]),
                      d.dir('riverpod-testing', [
                        d.file(
                          'SKILL.md',
                          '---\nname: riverpod-testing\n---\n',
                        ),
                      ]),
                    ]),
                    d.dir('flutter_riverpod', [
                      d.dir('flutter_riverpod-hooks', [d.file('SKILL.md', '')]),
                    ]),
                  ]),
                ]),
              ]),
            ]),
          ]),
        ]).create();

        const scanner = RegistryScanner();
        final skills = await scanner.scan(
          d.path('project'),
          isGlobal: false,
          repos: [
            registryRepo,
          ],
        );

        expect(skills, hasLength(3));
        expect(
          skills.map((s) => s.packageName).toSet(),
          equals({'riverpod', 'flutter_riverpod'}),
        );
        expect(
          skills.map((s) => s.skillName).toSet(),
          equals({
            'riverpod-get-started',
            'riverpod-testing',
            'flutter_riverpod-hooks',
          }),
        );
      },
    );

    test('when skill dir has no hyphen then skipped in flat layout', () async {
      await d.dir('project', [
        d.dir('.dart_tool', [
          d.dir('skills', [
            d.dir('repos', [
              d.dir('a', [
                d.dir('b', [
                  d.dir('skills', [
                    d.dir('no_hyphen', [
                      d.file('SKILL.md', '---\nname: no_hyphen\n---\n'),
                    ]),
                  ]),
                ]),
              ]),
            ]),
          ]),
        ]),
      ]).create();

      const scanner = RegistryScanner();
      final skills = await scanner.scan(
        d.path('project'),
        isGlobal: false,
        repos: [
          const RegistryRepo(
            cloneUrl: 'https://github.com/a/b.git',
          ),
        ],
      );
      expect(skills, isEmpty);
    });

    test('when skill dir has no SKILL.md then skipped', () async {
      await d.dir('project', [
        d.dir('.dart_tool', [
          d.dir('skills', [
            d.dir('repos', [
              d.dir('a', [
                d.dir('b', [
                  d.dir('skills', [
                    d.dir('pkg-skill', [d.file('README.md', 'not a skill')]),
                  ]),
                ]),
              ]),
            ]),
          ]),
        ]),
      ]).create();

      const scanner = RegistryScanner();
      final skills = await scanner.scan(
        d.path('project'),
        isGlobal: false,
        repos: [
          const RegistryRepo(
            cloneUrl: 'https://github.com/a/b.git',
          ),
        ],
      );
      expect(skills, isEmpty);
    });

    test('when multiple repos then aggregates skills from all', () async {
      const registryRepos = [
        RegistryRepo(
          cloneUrl: 'https://github.com/owner1/repo1.git',
        ),
        RegistryRepo(
          cloneUrl: 'https://github.com/owner2/repo2.git',
        ),
      ];
      await d.dir('project', [
        d.dir('.dart_tool', [
          d.dir('skills', [
            d.dir('repos', [
              d.dir(registryRepos[0].pathSegment, [
                d.dir('skills', [
                  d.dir('pkg-a', [d.file('SKILL.md', '')]),
                ]),
              ]),
              d.dir(registryRepos[1].pathSegment, [
                d.dir('skills', [
                  d.dir('pkg-b', [d.file('SKILL.md', '')]),
                ]),
              ]),
            ]),
          ]),
        ]),
      ]).create();

      const scanner = RegistryScanner();
      final skills = await scanner.scan(
        d.path('project'),
        isGlobal: false,
        repos: registryRepos,
      );
      expect(skills, hasLength(2));
      expect(skills.map((s) => s.packageName).toSet(), equals({'pkg'}));
      expect(
        skills.map((s) => s.skillName).toSet(),
        equals({'pkg-a', 'pkg-b'}),
      );
    });
  });
}
