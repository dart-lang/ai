# Agent instructions for the skills project

**What this project does:** A Dart CLI that installs Agent Skills from package dependencies into the user’s IDE. Package authors ship a `skills/` directory with their pub package; users run `skills get` and the CLI finds those skills in the dependency tree and installs them into Antigravity, Claude Code, Cline, Codex, Cursor, generic, or GitHub Copilot so the AI assistant understands the stack.

General rules for AI assistants working on this codebase.

## After adding or changing code

Always run these before considering the change done:

1. **Format:** `dart format .`
2. **Analyze:** `dart analyze --fatal-infos`
3. **Test:** `dart test`

Fix any format, analysis, or test failures before finishing.

## Project conventions

- **Manifest path:** The skills manifest path is defined in one place: `.dart_tool/skills/skills_config.json` (see `SkillManifest` in `lib/src/models/skill_manifest.dart`). Use `SkillManifest.pathIn(rootPath)`, `SkillManifest.dirName`, and `SkillManifest.baseName` — never hardcode the path or path separators elsewhere.
- **Paths:** Use `package:path/path.dart` and `p.join()` for all path construction so behavior is correct on Windows.
- **Empty manifest:** When all managed skills are removed, delete the `.dart_tool/skills` directory rather than leaving an empty manifest file (see `SkillManifest.cleanupDir` and `RemoveCommand`).
- **Workspace resolution:** The CLI supports (1) a directory with a `pubspec.yaml` (pub workspace, melos, or single package) and (2) an implicit workspace: no root `pubspec.yaml`, but immediate subdirectories that have `pubspec.yaml` are treated as packages. Do not walk up the directory tree to find a project root; the user is expected to run from the project root.
- **IDE install locations:** Install full Agent Skills (SKILL.md plus scripts, references, assets) into each IDE’s documented location: `.cursor/skills/`, `.agents/skills/`, `.claude/skills/`, `.cline/skills/`, `.github/skills/`. See README for spec links.
- **Registry repos:** GitHub registry repos are cloned/updated under `.dart_tool/skills/repos/<owner>/<repo>`. The merge step gives Dart-package skills precedence per package: if a dependency ships its own skills, registry skills for that package are not installed.
- **Generic IDE:** Antigravity, Codex, and generic are separate CLI options that all install to `.agents/skills/`. Only `generic` is stored in `skills_config.json`.
- **Listing IDEs:** When listing agents/IDEs (docs, help text, CLI options), use alphabetical order with generic last.
- **Cline** is experimental; **Copilot** is not auto-detected (use `--ide copilot` explicitly).
- **Tests** Always write tests for all new features that are added.

## Keeping instructions up to date

- **AGENTS.md:** When you discover a new convention, gotcha, or practice that would help future agents (or yourself in a later session), add it to this file. Prefer adding to the relevant section (e.g. project conventions) or creating a new bullet; keep the file scannable.
- **Skills:** This repo may ship skills (e.g. under `.cursor/skills/`, etc.). When you learn something that belongs in a skill — e.g. how to use the CLI, how to author skills, or project-specific patterns — update the relevant `SKILL.md` (or add a new skill) so that knowledge is persisted and available to the AI next time.
