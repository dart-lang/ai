# Changelog

## 0.4.0-dev

- feat: Added a dialog to select which packages to install skills from during
  `skills get` and `skills remove`.
- feat: Added a dialog to select which specific skills to install during
  `skills get` and `skills remove`.
- **Breaking Change**: Removed support for rest arguments, instead use the new
  `--package`, `--skill`, or `--all` options, or the built in dialogs.
- **Breaking Change**: `getSkills` now takes a set of package names to install
  instead of just a single package name. To install all skills pass the
  `allFlag: true` argument.
- refactor: Migrate from `.agent/skills` to `.agents/skills` for the generic IDE
  adapter. When a `.agent/` dir is detected you will be prompted for what action
  to take.
- feat: Added `DialogSupport` interface and optional parameter to `getSkills`,
  includes a `CliUtilDialogSupport` implementation for use in simple CLIs.
- feat: **Breaking Change** - Removed `stdout` and `stdin` parameters to
  `getSkills` and replaced them with a required `Logger logger`.
- feat: Check packages for security advisories on install.
- chore: Move cache dir to `.dart_tool/skills` from `.dart_skills`.
- feat: Allow the user to select an IDE if none is detected.
- feat: Add `registry` command with `add`, `list`, and `remove` commands. This
  replaces the old hardcoded flutter/skills and serverpod/skills-registry
  registries, and new installs will not get those auto installed.
- fix: **Breaking Change** - Only install skills from immediate dependencies.

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

- fix: Uses correct skills format for all IDEs.

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
