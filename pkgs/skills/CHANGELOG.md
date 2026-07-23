# Changelog

## 1.0.0-wip

- Emphasize (bold) actual skill names in interactive dialog options.
- JSON encode descriptions in the `create` command.

## 1.0.0-beta.4

- Update github repo link to the new location.

## 1.0.0-beta.3

- feat: Add some basic analytics tracking of commands ran and errors.

## 1.0.0-beta.2

- feat: Add a `create` command to assist with creating skills for users of the
  current package.

## 1.0.0-beta.1

- feat: Added a dialog to select which packages to install skills from during
  `skills get` and `skills remove`.
- feat: Added a dialog to select which specific skills to install during
  `skills get` and `skills remove`.
- **Breaking Change**: Removed support for rest arguments, instead use the new
  `--package`, `--skill`, `--git` or `--all` options, or the built in dialogs.
- **Breaking Change**: `getSkills` now takes a set of source uris to install
  instead of just a single package name. To install all skills pass the
  `allFlag: true` argument. Packages should be provided in `package:<name>`
  format instead of just by name.
- refactor: Migrate from `.agent/skills` to `.agents/skills` for the generic agent
  adapter. When a `.agent/` dir is detected you will be prompted for what action
  to take.
- feat: Added `DialogSupport` interface and optional parameter to `getSkills`,
  includes a `CliUtilDialogSupport` implementation for use in simple CLIs.
- feat: **Breaking Change** - Removed `stdout` and `stdin` parameters to
  `getSkills` and replaced them with a required `Logger logger`.
- feat: Check packages for security advisories on install.
- chore: Move cache dir to `.dart_tool/skills` from `.dart_skills`.
- feat: Allow the user to select an agent if none is detected.
- fix: **Breaking Change** - Only install skills from immediate dependencies.
- chore: **Breaking Change** - Drop support for the built in "registry" concept.
- feat: Add a general install from git concept, through the new `add` command,
  which maps very closely to how `npx skills add` works.
  - Many commands from https://skills.sh will now work, by simply substituting
  `npx skills` for `dart run skills@`.
  - The `get` command now supports `--git` arguments for git repos to update
    skills from.
- feat: Once per machine/project, suggest installing the dart and flutter
  skill repos, if they are not already installed.
- feat: Support `internal: true` metadata in frontmatter to skill internal
  skills, unless the `INSTALL_INTERNAL_SKILLS=1` environment variable is set.
- chore: Rename `--ide` option to `--agent` option, `--ide` will still work
  as an alias for some time.
- chore: **Breaking Change**: Renamed `IDE` enum to `Agent`.

## 0.3.1

- Allow config version 0.9.x.

## 0.3.0

- feat: Adds support for OpenCode.
- feat: Exports `getSkills` for programmatic usage as part of the public API.
- fix: Makes all skills non-user-invocable by default on Claude Code.

## 0.2.2

- refactor: Refactors the core logic to the `getSkills` function.

## 0.2.1

- docs: Updates README.

## 0.2.0

- feat: Adds `skills prune` command.
- chore: Lowers required Dart version.

## 0.1.5

- fix: Fixes git on Windows.

## 0.1.4

- feat: Adds support for fetching skills from GitHub repositories.

## 0.1.3

- fix: Uses correct skills format for all agents.

## 0.1.2

- fix: Fixes issue with monorepos.

## 0.1.1

- fix: Cleans up output from `skills get`.
- fix: Moves config file to `.dart_skills/skills_config.json`.
- chore: Adds tests for Windows.

## 0.1.0

- First working version.

## 0.0.1

- Initial version.
