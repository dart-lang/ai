# Skills

A CLI that brings AI agent skills from your Dart and Flutter package dependencies directly into your agent.

Dart packages can ship a `skills/` directory containing [Agent Skills](https://agentskills.io/specification), structured instructions that teach AI coding assistants how to use the package effectively. The `skills` CLI finds those skills in your dependency tree and installs them into your agent so your AI assistant better understands your stack.

## The problem

When you add a Dart package to your project, your AI coding assistant has no idea how to use it properly. It guesses APIs, invents patterns, and hallucinates methods that don't exist. You end up copy-pasting documentation into chat, writing custom rules, or correcting the AI over and over.

## The solution

Package authors ship skills alongside their code. You run one command, and your AI assistant knows how to work with every package in your project.

```bash
dart run skills@ get
```

Select the skills you would like to install, or pass `--all` to just install everything. Your AI assistant now has context-aware instructions for every dependency that provides skills.

## Quick start

Navigate to the root of your Dart or Flutter project and run:

```bash
# Install selected skills from all dependencies
dart run skills@ get

# Install skills from all dependencies without prompting
dart run skills@ get --all

# Install skills from a specific package
dart run skills@ get <package>

# List installed skills
dart run skills@ list

# Remove skills for packages no longer in your dependency tree
dart run skills@ prune

# Remove the selected managed skills
dart run skills@ remove

# Remove skills from one package
dart run skills@ remove serverpod

dart run skills@ add <git-url>
```

The CLI will automatically run `pub get` if needed, scan your dependency packages for `skills/` directories, and install them in the right location for your agent. If you are using a monorepo, `skills` will locate your different packages and get the skills for all of them.

### Installing skills from git

The `skills` package can also install skills from git repos, similar to how `npx skills` works. Given an `npx skills` command from https://skills.sh, you can substitute `npx skills` for `dart run skills@` to install them without the need for Node/NPX.

Once a repo has been added, future calls to `dart run skills@ get` will also check those repos for updates to skills.

- **Requirement:** Git must be installed and on your PATH. If git is not found, a warning is printed and only Dart package skills are used.

### Pruning removed dependencies

When you remove a package from your `pubspec.yaml`, its skills stay in your agent directories until you clean them up. Run:

```bash
dart run skills@ prune
```

This removes only skills whose package is no longer in your dependency tree and updates the manifest. Use `--agent <agent>` to prune a single agent. If you have no managed skills, `prune` reports that and exits.

### Version control and .gitignore

- If you **do not** version-control your agent config (`.agents`, etc), then you should include `.config/dart_skills` in your `.gitignore` as well
- If you **do** version control your agent config, then you should ensure sure that `.config/dart_skills` is **not** ignored. You may need to add `!.config/dart_skills` if you are ignoring the `.config` dir elsewhere in your git ignore.

## Supported agents

The CLI auto-detects your agent from project directory markers. If multiple agents are detected, it installs to all of them. You can also pass `--agent` explicitly or set the `SKILLS_AGENT` environment variable to target a single agent.

| agent | Flag | Install location | Spec |
| --- | ---- | ---------------- | ---- |
| [Antigravity](https://antigravity.google/docs/skills) | `--agent antigravity` | `.agents/skills/` | Agent Skills |
| [Claude Code](https://code.claude.com/docs/en/skills) | `--agent claude` | `.claude/skills/` | Agent Skills |
| [Cline](https://docs.cline.bot/customization/skills) | `--agent cline` | `.cline/skills/` | Agent Skills |
| [Codex](https://developers.openai.com/codex/skills/) | `--agent codex` | `.agents/skills/` | Agent Skills |
| [Cursor](https://cursor.com/docs/skills) | `--agent cursor` | `.cursor/skills/` | Agent Skills |
| [GitHub Copilot](https://docs.github.com/en/copilot/concepts/agents/about-agent-skills) | `--agent copilot` | `.github/skills/` | Agent Skills |
| [OpenCode](https://opencode.ai) | `--agent opencode` | `.opencode/skills/` | Agent Skills |
| Generic | `--agent generic` | `.agents/skills/` | Agent Skills |

Antigravity, Codex, and generic all install to the same `.agents/skills/` directory (only `generic` is stored in the config). GitHub Copilot is not auto-detected (`.github/` is often used for other purposes); use `--agent copilot` to install skills for Copilot explicitly.

Each of these agents receives the full Agent Skills directory (SKILL.md plus `scripts/`, `references/`, `assets/`) in each tool’s documented location.

## For package maintainers

Ship AI skills with your package so every user's coding assistant understands your APIs, conventions, and best practices.

### Adding skills to your package

Create a `skills/` directory at the root of your package (next to `lib/`). Each skill is a subdirectory containing a `SKILL.md` file following the [Agent Skills specification](https://agentskills.io/specification):

```
my_package/
  lib/
  skills/
    my_package-code-gen/
      SKILL.md
      scripts/       # optional helper scripts
      references/    # optional reference docs
      assets/        # optional static resources
    my_package-testing/
      SKILL.md
```

### Naming convention

Every skill directory name **must** start with your package name followed by a hyphen. The CLI verifies this on installation and silently skips any skills that don't follow the convention.

For a package named `serverpod`:

| Directory name | Valid? |
| -------------- | ------ |
| `serverpod-code-generation` | Yes |
| `serverpod-api-design` | Yes |
| `code-generation` | No -- missing package prefix |
| `other_pkg-code-generation` | No -- wrong prefix |

This convention ensures skill names are globally unique and self-documenting. When a user sees `serverpod-code-generation` in their agent, they know exactly where it came from.

### Writing a skill

The `name` field in `SKILL.md` should match the directory name. Here is an example of a skill:

```
---
name: my_package-my-skill
description: Use when the user is working with MyPackage APIs to ensure correct patterns and error handling.
---

# My Skill

## Guidelines

- Always use `MyPackage.initialize()` before calling other methods.
- Prefer the builder pattern for configuration.
- Handle `MyPackageException` explicitly rather than catching generic exceptions.

## Examples

...
```

The `description` tells the AI when to activate the skill -- make it specific and action-oriented.

### Supporting all agents

All agents receive the full skill directory (SKILL.md plus `scripts/`, `references/`, `assets/`). Write skills once and they install to each agent’s spec-defined location.

### Best practices

- **Keep skills focused.** One skill per major feature area. Don't dump everything into a single skill.
- **Write for the AI, not the human.** Skills are instructions for the coding assistant. Be direct and prescriptive.
- **Include examples.** Show correct usage patterns. The AI learns best from concrete examples.
- **Keep SKILL.md under 500 lines.** Move detailed reference material into `references/` files; all supported agents receive the full skill directory.
- **Version your skills with your package.** When you change APIs, update the skills to match.

### What happens when users run `dart run skills@ get`

1. The CLI resolves your package's location on disk from `package_config.json`.
2. It finds your `skills/` directory and each skill subdirectory with a `SKILL.md`.
3. It validates that each skill name starts with your package name.
4. It compares the current skills to any previously installed skills, presenting the user with relevant dialogs to update, install, or delete skills.
5. The selected skills are installed into the user's agent-specific location.
6. A `.config/dart_skills/skills_config.json` tracking file records information about all the available skills and their last known states.

Users can update skills by running `dart run skills@ get` again.

Users can remove skills by running `dart run skills@ remove`, which will read the `.config/dart_skills/skills_config.json` file so that it doesn't touch manually curated skills.
