import 'dart:io';

import 'git_runner.dart';
import 'registry_repos.dart';

/// Syncs GitHub registry repos to the local `.dart_skills/repos` directory.
///
/// If a repo is not yet cloned, clones it. If it exists, runs git fetch and
/// reset --hard to the remote HEAD. On clone/fetch failure, logs a warning
/// and continues (Dart-only skills are still used).
class RegistrySync {
  final GitRunner gitRunner;

  /// Repos to sync.
  final List<RegistryRepo> repos;

  const RegistrySync({GitRunner? gitRunner, this.repos = const []})
      : gitRunner = gitRunner ?? const GitRunner();

  /// Ensures all [repos] are present and up to date under
  /// [rootPath]/.dart_skills/repos.
  ///
  /// Call only when [GitRunner.isAvailable] is true.
  /// Creates .dart_skills/repos if needed. On per-repo errors, prints a
  /// warning to [stderr] and continues.
  Future<void> sync(
    String rootPath, {
    void Function(String)? onProgress,
  }) async {
    final reposDir = Directory(registryReposPath(rootPath));
    if (!await reposDir.exists()) {
      await reposDir.create(recursive: true);
    }

    for (final repo in repos) {
      final repoPath = registryRepoPath(rootPath, repo);
      final dir = Directory(repoPath);

      if (await dir.exists()) {
        await _update(repoPath, repo, onProgress);
      } else {
        await _clone(rootPath, repoPath, repo, onProgress);
      }
    }
  }

  Future<void> _clone(
    String rootPath,
    String repoPath,
    RegistryRepo repo,
    void Function(String)? onProgress,
  ) async {
    onProgress?.call('Cloning ${repo.cloneUrl}...');
    final result = await Process.run(
      'git',
      ['clone', '--depth', '1', repo.cloneUrl, repoPath],
      workingDirectory: rootPath,
      runInShell: true,
    );
    if (result.exitCode != 0) {
      stderr.writeln(
        'Warning: Failed to clone ${repo.cloneUrl}: ${result.stderr}',
      );
    }
  }

  Future<void> _update(
    String repoPath,
    RegistryRepo repo,
    void Function(String)? onProgress,
  ) async {
    onProgress?.call('Updating ${repo.cloneUrl}...');
    var result = await Process.run(
      'git',
      ['fetch', 'origin'],
      workingDirectory: repoPath,
      runInShell: true,
    );
    if (result.exitCode != 0) {
      stderr.writeln(
        'Warning: Failed to fetch ${repo.cloneUrl}: ${result.stderr}',
      );
      return;
    }
    result = await Process.run(
      'git',
      ['reset', '--hard', 'origin/HEAD'],
      workingDirectory: repoPath,
      runInShell: true,
    );
    if (result.exitCode != 0) {
      stderr.writeln(
        'Warning: Failed to reset ${repo.cloneUrl}: ${result.stderr}',
      );
    }
  }
}
