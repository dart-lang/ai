// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:unified_analytics/unified_analytics.dart';

import '../core/analytics.dart';
import '../core/dialog_support.dart';
import '../core/migration.dart';
import '../core/version.dart';

/// Custom CommandRunner that handles global options and runs migrations before commands.
class SkillsCommandRunner extends CommandRunner<void> {
  final DialogSupport? dialogSupport;

  SkillsCommandRunner(
    super.executableName,
    super.description, {
    this.dialogSupport,
  }) {
    argParser.addOption(
      'directory',
      abbr: 'C',
      help: 'Run as if in this directory (default: current directory).',
    );
  }

  @override
  Future<void> run(Iterable<String> args) async {
    try {
      final argResults = parse(args);

      try {
        analytics.send(
          Event.packageSkillsEvent(
            version: version,
            type: argResults.command?.name ?? 'no-command',
          ),
        );
      } catch (_) {}

      final dir = argResults.option('directory');
      final rootPath = dir != null
          ? p.normalize(p.absolute(dir))
          : Directory.current.path;

      if (!argResults.flag('help')) {
        await runMigrations(rootPath, dialogSupport);
      }

      return await runCommand(argResults);
    } catch (e) {
      try {
        analytics.send(
          Event.packageSkillsEvent(
            version: version,
            type: ErrorMetrics.type,
            additionalData: ErrorMetrics(e.runtimeType.toString()),
          ),
        );
      } catch (_) {}

      // Re-throw the error, we just want to log it first.
      rethrow;
    }
  }
}
