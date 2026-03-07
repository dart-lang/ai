import 'dart:io';

/// Checks whether git is available on the system.
///
/// Used to decide whether to clone/update GitHub registry repos;
/// if git is not installed, registry skills are skipped and a warning is shown.
class GitRunner {
  /// If set, used instead of actually running git (for tests).
  final Future<bool> Function()? isAvailableOverride;

  const GitRunner({this.isAvailableOverride});

  /// Returns true if `git` can be executed (e.g. `git --version` succeeds).
  Future<bool> get isAvailable async {
    if (isAvailableOverride != null) return isAvailableOverride!();
    try {
      final result = await Process.run('git', ['--version'], runInShell: true);
      return result.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }
}
