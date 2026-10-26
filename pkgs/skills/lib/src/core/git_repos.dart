import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../models/skill_manifest.dart';

/// A git repository with a clone URL.
class GitRepo {
  /// The URL to pass to `git clone`. Any compatible URI is allowed.
  final String cloneUrl;

  /// Absolute paths where this repo is installed.
  final List<String> installs;

  const GitRepo({required this.cloneUrl, this.installs = const []});

  GitRepo copyWith({String? cloneUrl, List<String>? installs}) {
    return GitRepo(
      cloneUrl: cloneUrl ?? this.cloneUrl,
      installs: installs ?? this.installs,
    );
  }

  factory GitRepo.fromJson(Map<String, dynamic> json) {
    final installs = (json['installs'] as List<Object?>?)?.cast<String>() ?? [];
    final cloneUrl = json['cloneUrl'] as String;
    return GitRepo(cloneUrl: cloneUrl, installs: installs);
  }

  Map<String, dynamic> toJson() {
    return {'cloneUrl': cloneUrl, 'installs': installs};
  }

  /// Returns a copy with a new install location added.
  GitRepo withInstall(String location) {
    if (installs.contains(location)) return this;
    return GitRepo(cloneUrl: cloneUrl, installs: [...installs, location]);
  }

  /// The path segment for this repo under [reposDir].
  String get pathSegment => Uri.encodeComponent(cloneUrl);
}

/// Returns the absolute path to the repos root under [rootPath]:
/// `<rootPath>/.dart_tool/skills/repos`.
String gitReposPath(String rootPath) {
  return p.join(rootPath, SkillManifest.cacheDirPath, 'repos');
}

/// Returns the absolute path where [repo] should be cloned under [rootPath]:
/// `<rootPath>/.dart_tool/skills/repos/<encoded-url>`.
String gitRepoPath(String rootPath, GitRepo repo) {
  return p.join(gitReposPath(rootPath), repo.pathSegment);
}

/// Parses a git repo argument into a [GitRepo].
GitRepo parseGitRepoArg(String arg, String usage) {
  // Handle org/repo format.
  if (arg.contains('/') && !arg.contains(':') && !arg.contains('@')) {
    final parts = arg.split('/');
    if (parts.length != 2) {
      throw UsageException(
        'Invalid git repo format: $arg. Expected <owner>/<repo> or a Git URI. '
        'If you intended this to be a file path, please a file:// URI instead.',
        usage,
      );
    }
    final url = 'https://github.com/${parts[0]}/${parts[1]}.git';
    return GitRepo(cloneUrl: url);
  } else {
    return GitRepo(cloneUrl: arg);
  }
}
