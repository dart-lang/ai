import 'package:args/command_runner.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:skills/src/core/git_repos.dart';
import 'package:skills/src/models/skill_manifest.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(() {
    Logger.root.onRecord.listen((r) => printOnFailure(r.toString()));
  });

  group('GitRepo', () {
    test('pathSegment encodes cloneUrl', () {
      const repo = GitRepo(cloneUrl: 'https://github.com/flutter/skills.git');
      expect(
        repo.pathSegment,
        equals(Uri.encodeComponent('https://github.com/flutter/skills.git')),
      );
    });
  });

  group('gitReposPath / gitRepoPath', () {
    test('gitReposPath includes .dart_tool/skills/repos', () {
      final path = gitReposPath('/project');
      expect(path, contains(p.join(SkillManifest.cacheDirPath, 'repos')));
    });

    test('gitRepoPath includes host, owner and repo', () {
      const repo = GitRepo(cloneUrl: 'https://github.com/flutter/skills.git');
      final path = gitRepoPath('/project', repo);
      expect(
        path,
        contains(
          p.join(
            SkillManifest.cacheDirPath,
            'repos',
            Uri.encodeComponent(repo.cloneUrl),
          ),
        ),
      );
    });
  });

  group('parseGitRepoArg', () {
    test('parses full https URL correctly', () {
      final repo = parseGitRepoArg('https://github.com/foo/bar.git', 'usage');
      expect(repo.cloneUrl, 'https://github.com/foo/bar.git');
    });
    test('parses SSH URL correctly', () {
      final repo = parseGitRepoArg('git@github.com:foo/bar.git', 'usage');
      expect(repo.cloneUrl, 'git@github.com:foo/bar.git');
    });

    test('parses file URI correctly', () {
      final repo = parseGitRepoArg('file://some/path', 'usage');
      expect(repo.cloneUrl, 'file://some/path');
    });

    test('parses owner/repo correctly', () {
      final repo = parseGitRepoArg('foo/bar', 'usage');
      expect(repo.cloneUrl, 'https://github.com/foo/bar.git');
    });

    test('throws UsageException for invalid format with slash', () {
      expect(
        () => parseGitRepoArg('foo/bar/baz', 'usage'),
        throwsA(isA<UsageException>()),
      );
    });
  });
}
