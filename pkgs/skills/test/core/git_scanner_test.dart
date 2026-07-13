import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:skills/src/core/git_repos.dart';
import 'package:skills/src/core/git_scanner.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  setUpAll(() {
    Logger.root.onRecord.listen((r) => printOnFailure(r.toString()));
  });

  group('GitScanner', () {
    test('when repos directory does not exist then returns empty', () async {
      await d.dir('project', []).create();
      const scanner = GitScanner();
      final skills = await scanner.scan(d.path('project'), isGlobal: false);
      expect(skills, isEmpty);
    });

    test(
      'when scanning flat layout then returns ScannedSkills with correct fields',
      () async {
        const gitRepo = GitRepo(cloneUrl: 'https://github.com/owner/repo.git');
        await d.dir('project', [
          d.dir('.dart_tool', [
            d.dir('skills', [
              d.dir('repos', [
                d.dir(gitRepo.pathSegment, [
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

        const scanner = GitScanner();
        final skills = await scanner.scan(
          d.path('project'),
          isGlobal: false,
          repos: [gitRepo],
        );

        expect(skills, hasLength(2));
        expect(
          skills.map((s) => s.skillName).toSet(),
          equals({'my_pkg-buttons', 'my_pkg-forms'}),
        );
        for (final s in skills) {
          expect(s.gitUrl, equals('https://github.com/owner/repo.git'));
          expect(s.skillPath, contains(p.join('skills', s.skillName)));
        }
      },
    );

    test(
      'when scanning groupedByPackage layout then returns ScannedSkills',
      () async {
        const gitRepo = GitRepo(cloneUrl: 'https://github.com/owner/repo.git');
        await d.dir('project', [
          d.dir('.dart_tool', [
            d.dir('skills', [
              d.dir('repos', [
                d.dir(gitRepo.pathSegment, [
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
                      d.dir('flutter_riverpod-hooks', [
                        d.file(
                          'SKILL.md',
                          '---\nname: flutter_riverpod-hooks\n---\n',
                        ),
                      ]),
                    ]),
                  ]),
                ]),
              ]),
            ]),
          ]),
        ]).create();

        const scanner = GitScanner();
        final skills = await scanner.scan(
          d.path('project'),
          isGlobal: false,
          repos: [gitRepo],
        );

        expect(skills, hasLength(3));
        expect(
          skills.map((s) => s.gitUrl).toSet(),
          equals({'https://github.com/owner/repo.git'}),
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

    test('when skill is internal then it is skipped', () async {
      final repo = const GitRepo(cloneUrl: 'https://github.com/a/b.git');
      await d.dir('project', [
        d.dir('.dart_tool', [
          d.dir('skills', [
            d.dir('repos', [
              d.dir(repo.pathSegment, [
                d.dir('skills', [
                  d.dir('pkg-internal', [
                    d.file(
                      'SKILL.md',
                      '---\nname: pkg-internal\nmetadata:\n  internal: true\n---\n',
                    ),
                  ]),
                ]),
              ]),
            ]),
          ]),
        ]),
      ]).create();

      const scanner = GitScanner();
      final skills = await scanner.scan(
        d.path('project'),
        isGlobal: false,
        repos: [repo],
      );
      expect(skills, isEmpty);
    });

    test('when skill dir has no SKILL.md then skipped', () async {
      final repo = const GitRepo(cloneUrl: 'https://github.com/a/b.git');
      await d.dir('project', [
        d.dir('.dart_tool', [
          d.dir('skills', [
            d.dir('repos', [
              d.dir(repo.pathSegment, [
                d.dir('skills', [
                  d.dir('pkg-skill', [d.file('README.md', 'not a skill')]),
                ]),
              ]),
            ]),
          ]),
        ]),
      ]).create();

      const scanner = GitScanner();
      final skills = await scanner.scan(
        d.path('project'),
        isGlobal: false,
        repos: [repo],
      );
      expect(skills, isEmpty);
    });

    test('when multiple repos then aggregates skills from all', () async {
      const gitRepos = [
        GitRepo(cloneUrl: 'https://github.com/owner1/repo1.git'),
        GitRepo(cloneUrl: 'https://github.com/owner2/repo2.git'),
      ];
      await d.dir('project', [
        d.dir('.dart_tool', [
          d.dir('skills', [
            d.dir('repos', [
              d.dir(gitRepos[0].pathSegment, [
                d.dir('skills', [
                  d.dir('pkg-a', [
                    d.file('SKILL.md', '---\nname: pkg-a\n---\n'),
                  ]),
                ]),
              ]),
              d.dir(gitRepos[1].pathSegment, [
                d.dir('skills', [
                  d.dir('pkg-b', [
                    d.file('SKILL.md', '---\nname: pkg-b\n---\n'),
                  ]),
                ]),
              ]),
            ]),
          ]),
        ]),
      ]).create();

      const scanner = GitScanner();
      final skills = await scanner.scan(
        d.path('project'),
        isGlobal: false,
        repos: gitRepos,
      );
      expect(skills, hasLength(2));
      expect(
        skills.map((s) => s.gitUrl).toSet(),
        equals({
          'https://github.com/owner1/repo1.git',
          'https://github.com/owner2/repo2.git',
        }),
      );
      expect(
        skills.map((s) => s.skillName).toSet(),
        equals({'pkg-a', 'pkg-b'}),
      );
    });
  });
}
