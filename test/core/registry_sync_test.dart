import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills/src/core/registry_repos.dart';
import 'package:skills/src/core/registry_sync.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  group('RegistrySync', () {
    test(
      'when repos dir does not exist then creates it and clones local repo',
      () async {
        await d.dir('project', []).create();
        final projectPath = d.path('project');

        await d.dir('local_repo', [
          d.dir('skills', [
            d.dir('pkg-skill', [d.file('SKILL.md', '')]),
          ]),
        ]).create();
        final localPath = p.normalize(p.absolute(d.path('local_repo')));
        expect(
          (await Process.run(
                  'git',
                  [
                    'init',
                  ],
                  workingDirectory: localPath))
              .exitCode,
          equals(0),
        );
        // Required for git commit in CI (no global user.name/user.email).
        await Process.run(
            'git',
            [
              'config',
              'user.email',
              'test@test',
            ],
            workingDirectory: localPath);
        await Process.run(
            'git',
            [
              'config',
              'user.name',
              'Test',
            ],
            workingDirectory: localPath);
        await Process.run('git', ['add', '.'], workingDirectory: localPath);
        expect(
          (await Process.run(
                  'git',
                  [
                    'commit',
                    '-m',
                    'init',
                  ],
                  workingDirectory: localPath))
              .exitCode,
          equals(0),
        );

        String fileUrl;
        if (Platform.isWindows) {
          fileUrl = 'file:///${localPath.replaceAll(r'\', '/')}';
        } else {
          fileUrl = 'file://$localPath';
        }

        // Use customCloneUrl to point at local repo so we don't hit network
        final syncWithLocal = RegistrySync(
          repos: [
            RegistryRepo(
              cloneUrl: fileUrl,
            ),
          ],
        );
        await syncWithLocal.sync(projectPath);

        final reposDir = Directory(registryReposPath(projectPath));
        expect(await reposDir.exists(), isTrue);
        final repoDir = Directory(
          registryRepoPath(
            projectPath,
            RegistryRepo(
              cloneUrl: fileUrl,
            ),
          ),
        );
        expect(await repoDir.exists(), isTrue);
        final skillDir = Directory(p.join(repoDir.path, 'skills', 'pkg-skill'));
        expect(await skillDir.exists(), isTrue);
        expect(await File(p.join(skillDir.path, 'SKILL.md')).exists(), isTrue);
      },
    );

    test(
      'when sync given empty repos list then creates repos dir only',
      () async {
        await d.dir('project', []).create();
        const sync = RegistrySync(repos: []);
        await sync.sync(d.path('project'));
        final reposDir = Directory(registryReposPath(d.path('project')));
        expect(await reposDir.exists(), isTrue);
      },
    );
  });
}
