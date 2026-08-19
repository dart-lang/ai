// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../core/exceptions.dart';
import 'skills_command.dart';

class CreateCommand extends SkillsCommand {
  @override
  final String name = 'create';

  @override
  final String description =
      'Create a new skill for consumers of the current package.';

  CreateCommand() {
    argParser
      ..addOption(
        'name',
        abbr: 'n',
        help: 'The name of the skill to create (without package name prefix).',
      )
      ..addOption(
        'description',
        abbr: 'd',
        help: 'A short description of the skill.',
      );
  }

  @override
  Future<void> run() async {
    final argResults = this.argResults!;
    final workspace = await resolveWorkspace();
    final package = workspace.packages.firstWhere(
      (p) => p.path == workspace.rootPath,
    );

    var skillName = argResults.option('name')?.trim();
    var description = argResults.option('description')?.trim();

    if (skillName != null) {
      if (_isValidSkillName(skillName) case final message?) {
        throw UsageException(message, usage);
      }
    }
    while (skillName == null) {
      stdout.write('Skill Name (without package name prefix): ');
      final input = stdin.readLineSync();
      if (input == null) throw UserAbortException('Aborted by user.');

      final trimmed = input.trim();
      if (trimmed.isEmpty) {
        logger.severe('Skill name cannot be empty.');
        continue;
      }

      if (_isValidSkillName(trimmed) case final message?) {
        logger.severe(message);
        continue;
      }

      skillName = trimmed;
    }

    if (description == null) {
      stdout.write('Description: ');
      description = stdin.readLineSync()?.trim();
      if (description == null) throw UserAbortException('Aborted by user.');
    }

    if (description.isEmpty) {
      throw UsageException('Description is required.', usage);
    }

    final prefix = package.name.replaceAll('_', '-');
    final fullSkillName = '$prefix-$skillName';

    final skillsDir = Directory(p.join(package.path, 'skills', fullSkillName));

    if (await skillsDir.exists()) {
      throw UsageException(
        'Skill directory ${skillsDir.path} already exists. Cannot overwrite an existing skill.',
        usage,
      );
    }

    await skillsDir.create(recursive: true);

    final skillFile = File(p.join(skillsDir.path, 'SKILL.md'));
    await skillFile.writeAsString(_template(fullSkillName, description));

    logger.info(
      'Created empty skill in ${skillFile.path}, open that file and fill out '
      'the content.',
    );
  }
}

/// Checks if [name] is valid.
///
/// Returns `null` if it is, otherwise an error message.
String? _isValidSkillName(String name) {
  if (!_validNameRegex.hasMatch(name)) {
    return 'Invalid skill name. Only lowercase letters, numbers, and hyphens '
        'are allowed.';
  }
  return null;
}

/// Skill names can only have letters/numbers and hyphens.
final _validNameRegex = RegExp(r'^[a-z0-9-]+$');

String _template(String fullSkillName, String description) =>
    '''---
name: $fullSkillName
description: ${jsonEncode(description)}
---

# $fullSkillName

Brief overview of what this skill does and what it enables the agent to do.

## Instructions

Step-by-step instructions for the agent to follow:

1. Step one...
2. Step two...

## Guidelines

- Use clear, imperative language (e.g., "Run X", "Verify Y").
- Include concrete examples of inputs and expected outputs where helpful.
- Keep `SKILL.md` concise; move detailed reference docs to `references/` and helper scripts to `scripts/`.
''';
