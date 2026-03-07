import 'core/registry_repos.dart';

/// Hardcoded list of GitHub registry repositories and their layout.
const List<RegistryRepo> kRegistryRepos = [
  RegistryRepo(
    owner: 'flutter',
    name: 'skills',
    skillLayout: RegistrySkillLayout.flat,
  ),
  RegistryRepo(
    owner: 'serverpod',
    name: 'skills-registry',
    skillLayout: RegistrySkillLayout.groupedByPackage,
  ),
];
