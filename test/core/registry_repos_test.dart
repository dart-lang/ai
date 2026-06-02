import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:skills/src/core/registry_repos.dart';
import 'package:skills/src/models/skill_manifest.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(() {
    Logger.root.onRecord.listen((r) => printOnFailure(r.toString()));
  });

  group('RegistryRepo', () {
    test('pathSegment encodes cloneUrl', () {
      const repo = RegistryRepo(
        cloneUrl: 'https://github.com/flutter/skills.git',
      );
      expect(repo.pathSegment,
          equals(Uri.encodeComponent('https://github.com/flutter/skills.git')));
    });

    test('cloneUrl is the provided URL', () {
      const repo = RegistryRepo(
        cloneUrl: 'https://example.com/repo.git',
      );
      expect(
        repo.cloneUrl,
        equals('https://example.com/repo.git'),
      );
    });
  });

  group('registryReposPath / registryRepoPath', () {
    test('registryReposPath includes .dart_tool/skills/repos', () {
      final path = registryReposPath('/project');
      expect(path, contains(p.join(SkillManifest.cacheDirPath, 'repos')));
    });

    test('registryRepoPath includes host, owner and repo', () {
      const repo = RegistryRepo(
        cloneUrl: 'https://github.com/flutter/skills.git',
      );
      final path = registryRepoPath('/project', repo);
      expect(
        path,
        contains(p.join(SkillManifest.cacheDirPath, 'repos',
            Uri.encodeComponent(repo.cloneUrl))),
      );
    });
  });
}
