import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:skills/src/core/exceptions.dart';

import '../core/dialog_support.dart';
import '../core/git_repos.dart';
import '../core/skill_installer.dart';
import '../ide/ide.dart';
import '../models/global_config.dart';
import '../models/skill_manifest.dart';

final _logger = Logger('Migration');

/// Runs all migrations.
Future<void> runMigrations(
  String rootPath,
  DialogSupport? dialogSupport,
) async {
  await SkillManifest.migrateIfNeeded(rootPath);
  final manifestFile = File(SkillManifest.pathIn(rootPath));
  final manifest = await SkillManifest.loadOrEmpty(manifestFile);

  var updatedManifest = maybeMigratePackageUris(manifest);

  updatedManifest = await maybeDoRegistryMigration(
    rootPath,
    updatedManifest,
    dialogSupport,
  );

  // All migrations finished, update the version to the latest if it isn't
  // already. We wait until the end to do this so all migrations see the
  // original version.
  if (manifest.version != SkillManifest.currentVersion) {
    updatedManifest = SkillManifest(
      version: SkillManifest.currentVersion,
      installations: updatedManifest.installations,
    );
  }

  if (updatedManifest != manifest) {
    await updatedManifest.save(manifestFile);
  }
}

/// Migrates registries to repos if version < 2.
Future<SkillManifest> maybeDoRegistryMigration(
  String rootPath,
  SkillManifest manifest,
  DialogSupport? dialogSupport,
) async {
  if (manifest.version >= 2) {
    return manifest;
  }

  var updatedManifest = manifest;

  final globalConfigPath = GlobalConfig.globalPath;
  final globalConfigFile = File(globalConfigPath);
  var globalConfig = await GlobalConfig.loadOrEmpty(globalConfigFile);

  final reposDirPath = gitReposPath(rootPath);
  final reposDir = Directory(reposDirPath);
  if (!await reposDir.exists()) {
    return updatedManifest;
  }

  final existingRepos = <GitRepo>[];
  try {
    await for (final entity in reposDir.list()) {
      if (entity is Directory) {
        final owner = p.basename(entity.path);
        await for (final subEntity in entity.list()) {
          if (subEntity is Directory) {
            final name = p.basename(subEntity.path);
            existingRepos.add(
              GitRepo(cloneUrl: 'https://github.com/$owner/$name.git'),
            );
          }
        }
      }
    }
  } catch (e) {
    // Ignore errors listing directories.
  }

  final reposToMigrate = <GitRepo>[];
  for (final repo in existingRepos) {
    if (globalConfig.gitRepos.any((r) => r.cloneUrl == repo.cloneUrl)) {
      _logger.info(
        'Skipping migration for ${repo.cloneUrl} as it is already in global '
        'config.',
      );
      continue;
    }
    reposToMigrate.add(repo);
  }

  if (reposToMigrate.isEmpty) {
    return updatedManifest;
  }

  if (dialogSupport case var dialogSupport?) {
    if (reposToMigrate.isNotEmpty) {
      _logger.warning(
        'Registry support has been replaced with raw git repo support. Please '
        'choose how you would like to handle the migrations for your existing '
        'registries.',
      );
    }
    for (final repo in reposToMigrate) {
      final options = [
        'keep this repo and its skills installed globally',
        'keep this repo and its skills installed only for this project',
        'remove this repository but keep its skills installed',
        'remove this repository and uninstall its skills',
      ];
      final index = await dialogSupport.showSingleSelectDialog(
        options,
        title:
            'Found installed skill repository ${repo.cloneUrl} during '
            'migration, would you like to:',
      );

      if (index != null) {
        // Previous registries were hard coded to just a couple github
        // registries, so this code has some assumptions about github URIs.
        final uri = Uri.parse(repo.cloneUrl);
        final owner = uri.pathSegments[uri.pathSegments.length - 2];
        final name = uri.pathSegments.last.replaceAll('.git', '');
        final repoPath = p.join(reposDirPath, owner, name);
        final repoDir = Directory(repoPath);

        // Keep the repo, locally or globally installed
        if (index == 0 || index == 1) {
          if (index == 0) {
            globalConfig = globalConfig.withGitRepo(repo);
          }
          updatedManifest = await _migrateRepoLocally(
            repo,
            updatedManifest,
            reposDirPath,
            repoDir,
          );
        } else if (index > 2) {
          // Final two options both remove the repo, but only option 3
          // uninstalls the skills.
          if (index == 3) {
            final installer = SkillInstaller(dialogSupport);
            final skillsToRemove = <String>{};
            if (await repoDir.exists()) {
              await for (final entity in repoDir.list(recursive: true)) {
                if (entity is File && p.basename(entity.path) == 'SKILL.md') {
                  skillsToRemove.add(p.basename(entity.parent.path));
                }
              }
            }
            if (skillsToRemove.isNotEmpty) {
              for (final ideName in updatedManifest.allIdes.toList()) {
                final ide = Ide.fromCliName(ideName)!;
                final result = await installer.removeSkillsForIde(
                  ide: ide,
                  rootPath: rootPath,
                  manifest: updatedManifest,
                  skillNames: skillsToRemove,
                );
                updatedManifest = result.manifest;
              }
            }
          }
          // Remove this repository from disk
          if (await repoDir.exists()) {
            await repoDir.delete(recursive: true);
            _logger.info('Deleted local clone for ${repo.cloneUrl} from disk.');

            // Clean up owner dir if empty
            final ownerDir = repoDir.parent;
            if (await ownerDir.exists() && (await ownerDir.list().isEmpty)) {
              await ownerDir.delete();
            }
          }
        }
      } else {
        throw UserAbortException(
          'Migration cancelled by user for ${repo.cloneUrl}',
        );
      }
    }
    await globalConfig.save(globalConfigFile);
  } else {
    for (final repo in reposToMigrate) {
      final uri = Uri.tryParse(repo.cloneUrl);
      final owner = uri!.pathSegments[uri.pathSegments.length - 2];
      final name = uri.pathSegments.last.replaceAll('.git', '');
      final repoPath = p.join(reposDirPath, owner, name);
      final repoDir = Directory(repoPath);

      updatedManifest = await _migrateRepoLocally(
        repo,
        updatedManifest,
        reposDirPath,
        repoDir,
      );
      _logger.info(
        'Automatically kept ${repo.cloneUrl} local (non-interactive).',
      );
    }
  }

  return SkillManifest(
    version: manifest.version,
    installations: updatedManifest.installations,
  );
}

/// Migrates old raw package names to `package:` URIs if version < 2.
SkillManifest maybeMigratePackageUris(SkillManifest manifest) {
  if (manifest.version >= 2) {
    return manifest;
  }

  var updatedManifest = manifest;
  for (final ideName in updatedManifest.allIdes.toList()) {
    final idePkgs = updatedManifest.sourceUrisForIde(ideName);
    for (final pkgEntry in idePkgs.entries.toList()) {
      if (!pkgEntry.key.startsWith('package:') &&
          !pkgEntry.key.startsWith('https://')) {
        updatedManifest = updatedManifest.withoutSourceUri(
          ideName,
          pkgEntry.key,
        );
        updatedManifest = updatedManifest.withSourceUri(
          ideName,
          'package:${pkgEntry.key}',
          pkgEntry.value,
        );
      }
    }
  }

  return updatedManifest;
}

/// Migrates [repo] to the new install location and updates
/// [manifest] with any installed skills.
Future<SkillManifest> _migrateRepoLocally(
  GitRepo repo,
  SkillManifest manifest,
  String reposDirPath,
  Directory repoDir,
) async {
  var updatedManifest = manifest;

  // Directory names of all the skills we found in the repo.
  final skillsInRepo = <String>{};
  if (await repoDir.exists()) {
    await for (final entity in repoDir.list(recursive: true)) {
      if (entity is File && p.basename(entity.path) == 'SKILL.md') {
        skillsInRepo.add(p.basename(entity.parent.path));
      }
    }
  }

  // Migrate the manifest entries for any skills from the repo
  for (final ideName in updatedManifest.allIdes.toList()) {
    final idePkgs = updatedManifest.sourceUrisForIde(ideName);
    var repoSkills = <InstalledSkillEntry>[];

    for (final pkgEntry in idePkgs.entries) {
      if (pkgEntry.key.startsWith('package:')) {
        final skillsToKeep = <InstalledSkillEntry>[];
        for (final skill in pkgEntry.value.skills) {
          if (skillsInRepo.contains(skill.name)) {
            repoSkills.add(skill);
          } else {
            skillsToKeep.add(skill);
          }
        }
        if (skillsToKeep.length != pkgEntry.value.skills.length) {
          if (skillsToKeep.isEmpty) {
            updatedManifest = updatedManifest.withoutSourceUri(
              ideName,
              pkgEntry.key,
            );
          } else {
            updatedManifest = updatedManifest.withSourceUri(
              ideName,
              pkgEntry.key,
              SkillsEntry(skills: skillsToKeep),
            );
          }
        }
      }
    }

    if (repoSkills.isNotEmpty) {
      final existingRepoEntry = updatedManifest.sourceUrisForIde(
        ideName,
      )[repo.cloneUrl];
      if (existingRepoEntry != null) {
        repoSkills = [...existingRepoEntry.skills, ...repoSkills];
      }
      updatedManifest = updatedManifest.withSourceUri(
        ideName,
        repo.cloneUrl,
        SkillsEntry(skills: repoSkills),
      );
    }
  }

  // Rename old directory to new URL-encoded format
  final newPath = p.join(reposDirPath, Uri.encodeComponent(repo.cloneUrl));
  final newDir = Directory(newPath);
  if (await repoDir.exists() && !await newDir.exists()) {
    await repoDir.rename(newPath);
    _logger.info('Renamed local clone for ${repo.cloneUrl} to new format.');

    // Clean up owner dir if empty
    final ownerDir = repoDir.parent;
    if (await ownerDir.exists() && (await ownerDir.list().isEmpty)) {
      await ownerDir.delete();
    }
  }

  return updatedManifest;
}
