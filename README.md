# Skills

A CLI that brings AI agent skills from your Dart and Flutter package dependencies directly into your IDE.

> Note: The Dart team is working on a [similar solution](https://docs.google.com/document/d/1k_X-Sp4GQyZP6k9lvZ1Itj0GvzQZuWl3iKzi5AIa69Q/edit?tab=t.0) based on Dart's MCP server. When that is released, we will provide scripts to convert your skills to Dart's new format. This package will then either adopt the Dart MCP standard for delivering skills or be deprecated (assuming the MCP solution is equally capable).

Dart packages can ship a `skills/` directory containing [Agent Skills](https://agentskills.io/specification), structured instructions that teach AI coding assistants how to use the package effectively. The `skills` CLI finds those skills in your dependency tree and installs them into your IDE so your AI assistant better understands your stack.

## The problem

When you add a Dart package to your project, your AI coding assistant has no idea how to use it properly. It guesses APIs, invents patterns, and hallucinates methods that don't exist. You end up copy-pasting documentation into chat, writing custom rules, or correcting the AI over and over.

## The solution

Package authors ship skills alongside their code. You run one command, and your AI assistant knows how to work with every package in your project.

```bash
skills get
```

That's it. Your AI assistant now has context-aware instructions for every dependency that provides skills.

## Installation

Activate the CLI globally:

```bash
dart pub global activate skills
```

Make sure `~/.pub-cache/bin` is on your PATH ([instructions](https://dart.dev/tools/pub/cmd/pub-global#running-a-script-from-your-path)).

## Quick start

Navigate to the root of your Dart or Flutter project and run:

```bash
# Install skills from all dependencies
skills get

# Install skills from a specific package
skills get serverpod

# List installed skills
skills list

# Remove all managed skills
skills remove

# Remove skills from one package
skills remove serverpod
```

The CLI will automatically run `pub get` if needed, scan your dependency packages for `skills/` directories, and install them in the right location for your IDE. If you are using a monorepo, `skills` will locate your different packages and get the skills for all of them.

## Supported IDEs

The CLI auto-detects your IDE from project directory markers. If multiple IDEs are detected, it installs to all of them. You can also pass `--ide` explicitly or set the `SKILLS_IDE` environment variable to target a single IDE.

| IDE | Flag | Install location | Spec |
| --- | ---- | ---------------- | ---- |
| Cursor | `--ide cursor` | `.cursor/skills/` | Agent Skills |
| Antigravity | `--ide antigravity` | `.agent/skills/` | Agent Skills |
| Claude Code | `--ide claude` | [`.claude/skills/`](https://code.claude.com/docs/en/skills) | Agent Skills |
| Cline (experimental) | `--ide cline` | [`.cline/skills/`](https://docs.cline.bot/customization/skills) | Agent Skills |
| GitHub Copilot | `--ide copilot` | [`.github/skills/`](https://docs.github.com/en/copilot/concepts/agents/about-agent-skills) | Agent Skills |

GitHub Copilot is not auto-detected (`.github/` is often used for other purposes). Use `--ide copilot` to install skills for Copilot explicitly.

All five IDEs receive the full Agent Skills directory (SKILL.md plus `scripts/`, `references/`, `assets/`) in each tool’s documented location.

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

This convention ensures skill names are globally unique and self-documenting. When a user sees `serverpod-code-generation` in their IDE, they know exactly where it came from.

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

### Supporting all IDEs

All IDEs receive the full skill directory (SKILL.md plus `scripts/`, `references/`, `assets/`). Write skills once and they install to each IDE’s spec-defined location.

### Best practices

- **Keep skills focused.** One skill per major feature area. Don't dump everything into a single skill.
- **Write for the AI, not the human.** Skills are instructions for the coding assistant. Be direct and prescriptive.
- **Include examples.** Show correct usage patterns. The AI learns best from concrete examples.
- **Keep SKILL.md under 500 lines.** Move detailed reference material into `references/` files; all supported IDEs receive the full skill directory.
- **Version your skills with your package.** When you change APIs, update the skills to match.

### What happens when users run `skills get`

1. The CLI resolves your package's location on disk from `package_config.json`.
2. It finds your `skills/` directory and each skill subdirectory with a `SKILL.md`.
3. It validates that each skill name starts with your package name.
4. Skills are installed into the user's IDE-specific location.
5. A `.dart_skills/skills_config.json` tracking file records which skills were installed from which package and IDE.

Users can update skills by running `skills get` again. Existing skills from your package are replaced with the latest versions.

The `.dart_skills/skills_config.json` file tracks managed skills so `skills remove` knows what to clean up without touching skills you created manually.
