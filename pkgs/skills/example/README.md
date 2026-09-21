# Examples

`skills` is a command line tool, so these examples are shell commands rather
than Dart code. Run them from the root of your Dart or Flutter project.

## Using skills in your project

Install skills from your dependencies into your agent. The CLI auto-detects
which agents you use and prompts you to choose the skills to install:

```bash
dart run skills@ get
```

Install everything without prompting — useful in CI or a setup script:

```bash
dart run skills@ get --all
```

Install skills from a single package, for a single agent:

```bash
dart run skills@ get serverpod --agent claude
```

Install skills from a git repository (the repo is remembered, and future
`get` runs will check it for updates):

```bash
dart run skills@ add dart-lang/ai
```

See what is currently installed:

```bash
dart run skills@ list
```

Remove skills for packages that are no longer in your dependency tree:

```bash
dart run skills@ prune
```

Remove specific managed skills, or all skills from one package:

```bash
dart run skills@ remove
dart run skills@ remove serverpod
```

## Shipping skills with your own package

Scaffold a new skill in your package. This prompts for a name and description
and creates `skills/<your_package>-<skill-name>/SKILL.md`, creating the
top-level `skills/` directory if needed:

```bash
dart run skills@ create
```

The resulting layout looks like this:

```
my_package/
  lib/
  skills/
    my-package-code-gen/
      SKILL.md
      scripts/       # optional helper scripts
      references/    # optional reference docs
      assets/        # optional static resources
```

And a minimal `SKILL.md`:

```markdown
---
name: my-package-code-gen
description: Use when generating code with MyPackage to ensure correct builder
  configuration and output locations.
---

# Code generation with MyPackage

## Guidelines

- Always run `dart run build_runner build` after changing an annotated class.
- Generated files end in `.g.dart` and must not be edited by hand.
```

Skill directory names must start with your package name (underscores may be
replaced with hyphens) followed by a hyphen, otherwise the CLI skips them.

See the [README](https://pub.dev/packages/skills) for the full list of
supported agents, install locations, and authoring guidance.
