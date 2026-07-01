import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:skills/src/core/git_repos.dart';
import 'package:skills/src/core/git_sync.dart';
import 'package:skills/src/models/skill_manifest.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  setUpAll(() {
    Logger.root.onRecord.listen((r) => printOnFailure(r.toString()));
  });
  group('GitSync', () {
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
          (await Process.run('git', [
            'init',
          ], workingDirectory: localPath)).exitCode,
          equals(0),
        );
        // Required for git commit in CI (no global user.name/user.email).
        await Process.run('git', [
          'config',
          'user.email',
          'test@test',
        ], workingDirectory: localPath);
        await Process.run('git', [
          'config',
          'user.name',
          'Test',
        ], workingDirectory: localPath);
        await Process.run('git', ['add', '.'], workingDirectory: localPath);
        expect(
          (await Process.run('git', [
            'commit',
            '-m',
            'init',
          ], workingDirectory: localPath)).exitCode,
          equals(0),
        );

        String fileUrl;
        if (Platform.isWindows) {
          fileUrl = 'file:///${localPath.replaceAll(r'\', '/')}';
        } else {
          fileUrl = 'file://$localPath';
        }

        // Use customCloneUrl to point at local repo so we don't hit network
        final gitRepo = GitRepo(cloneUrl: fileUrl);
        final syncWithLocal = GitSync(repos: [gitRepo]);
        await syncWithLocal.sync(projectPath);

        await d.dir('project', [
          d.dir(SkillManifest.cacheDirPath, [
            d.dir('repos', [
              d.dir(gitRepo.pathSegment, [
                d.dir('skills', [
                  d.dir('pkg-skill', [d.file('SKILL.md')]),
                ]),
              ]),
            ]),
          ]),
        ]).validate();
      },
    );

    test(
      'when sync given empty repos list then creates repos dir only',
      () async {
        await d.dir('project', []).create();
        const sync = GitSync(repos: []);
        await sync.sync(d.path('project'));
        final reposDir = Directory(gitReposPath(d.path('project')));
        expect(await reposDir.exists(), isTrue);
      },
    );
  });
}
