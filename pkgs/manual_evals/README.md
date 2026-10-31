# manual_evals

**Experimental**: This package is under active development. We might make changes to the Dart APIs and skills.

A suite of skills and evaluation tools designed for AI agents to benchmark skills, inspect environments, analyze tool usage, and conduct automated A/B evaluations.

## Installation

You can install the skills in this repository into your project using [`package:skills`](https://pub.dev/packages/skills) or `npx skills`:

```bash
# Using package:skills
dart run skills@ add https://github.com/dart-lang/ai.git

# Or using npx skills
npx skills add dart-lang/ai
```

### How Skill Scripts Work

Each skill with helper scripts in this package ships its own `pubspec.yaml` directly alongside its `SKILL.md` and `scripts/` directory in your agent's skills directory (for example, `.agents/skills/`, `.claude/skills/`, `.cursor/skills/`, etc.):

```text
<agent-dir>/
└── skills/
    └── manual-evals-example/
        ├── SKILL.md
        ├── pubspec.yaml
        └── scripts/
            └── run.dart
```

When an agent runs a skill script from the skill's directory:

```bash
dart run scripts/run.dart
```

`dart run` automatically locates the skill's `pubspec.yaml` and resolves its dependencies (including `package:manual_evals` from pub.dev) in the global `.pub-cache/` without requiring you to add `manual_evals` to your project's own `pubspec.yaml`.

### `.gitignore` Configuration

Because running a skill script with `dart run` generates `.dart_tool/` and `pubspec.lock` inside that skill's directory, if you check your installed skills into version control, add the following rules to your project's `.gitignore`:

```gitignore
**/skills/**/.dart_tool/
**/skills/**/pubspec.lock
```

## Local Development

When developing skills and shared library code locally in `pkgs/manual_evals`, each skill's `pubspec.yaml` depends on the published `manual_evals` package on pub.dev. To test unpublished local changes to `lib/`, create a `pubspec_overrides.yaml` file inside the skill directory (which is ignored by `.gitignore`):

```yaml
# skills/<skill-name>/pubspec_overrides.yaml
dependency_overrides:
  manual_evals:
    path: ../..
```

### Testing Skills from a Local Checkout

To test installing and running these skills in another project from a local `dart-lang/ai` checkout (or before `package:manual_evals` is published to pub.dev), pass a `file://` URI to `dart run skills@ add`:

```bash
dart run skills@ add file:///path/to/local/ai
```

Because `skills add` clones from your local Git history, commit your changes first so they are included. Then, if `package:manual_evals` is not yet published on pub.dev or has unpublished local changes, add a `pubspec_overrides.yaml` file inside the installed skill directory (e.g., `.agents/skills/<skill-name>/pubspec_overrides.yaml`) pointing to your local `pkgs/manual_evals` directory:

```yaml
dependency_overrides:
  manual_evals:
    path: /path/to/local/ai/pkgs/manual_evals
```

### Checking the Transcript Format

This package reads agent conversation transcripts, whose format belongs to the agent runtime and can change without notice. Because transcripts are read leniently, a format change shows up as missing data rather than an error. To check that the package still understands them, run this from inside an agent, ideally in a conversation with subagents:

```bash
dart run tool/check_transcript_format.dart [conversation-id]
```

Without an ID, it checks the current conversation. If the transcripts weren't fully understood, it lists the problems and exits with a non-zero code.

## Skill Naming Convention

All skill directories in `skills/` must begin with `manual-evals-` (or `manual_evals-`) and have a matching `name` in their `SKILL.md` frontmatter so they are discoverable by [`package:skills`](https://pub.dev/packages/skills).
