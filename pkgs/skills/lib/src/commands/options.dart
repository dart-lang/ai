// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io' show Platform;

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:skills/src/core/dialog_support.dart';

import '../agent/agent.dart';

const installDirOption = 'install-dir';

/// Parses the --agent option from [argResults].
/// Returns the agents that were specified via --agent.
List<Agent> parseAgentOption(ArgResults argResults) {
  if (!argResults.options.contains('agent') || !argResults.wasParsed('agent')) {
    return [];
  }
  final parsedAgents = argResults.multiOption('agent');
  // Agent names are already validated by the `allowed` list on the option.
  return [for (var agent in parsedAgents) Agent.fromCliName(agent)!];
}

/// Registers the shared `--agent` option on [argParser].
void addAgentOption(ArgParser argParser) {
  argParser.addMultiOption(
    'agent',
    aliases: ['ide'],
    help: 'Target agent',
    allowed: Agent.cliNames,
  );
}

/// Registers the shared `--install-dir` option on [argParser].
void addInstallDirOption(ArgParser argParser) {
  argParser.addOption(
    installDirOption,
    abbr: 'd',
    help:
        'Custom directory to install skills to (implicitly uses custom agent).',
  );
}

/// Parses the --install-dir option from [argResults].
String? parseInstallDirOption(ArgResults argResults) {
  if (argResults.options.contains(installDirOption) &&
      argResults.wasParsed(installDirOption)) {
    return argResults.option(installDirOption);
  }
  return null;
}

/// Returns the agents to operate on.
///
/// If `--install-dir` is specified, returns `[Agent.custom]`.
/// If `--agent` is specified (or the `SKILLS_AGENT` env var), returns that single
/// agent. Otherwise returns all auto-detected agents.
///
/// If no agent is auto-detected, uses [DialogSupport] (if given) to ask the user.
///
/// Throws if no agent can be determined.
Future<List<Agent>> resolveAgents({
  required ArgResults? argResults,
  required String projectPath,
  DialogSupport? dialogSupport,
  String usage = '',
}) async {
  if (argResults != null) {
    final customInstallDir = parseInstallDirOption(argResults);
    final parsedAgents = parseAgentOption(argResults);
    if (customInstallDir != null && parsedAgents.isNotEmpty) {
      throw UsageException(
        'Cannot specify both --agent and --install-dir.',
        usage,
      );
    }
    if (customInstallDir != null) {
      if (customInstallDir.trim().isEmpty) {
        throw UsageException(
          '--install-dir requires a non-empty directory path.',
          usage,
        );
      }
      return [Agent.custom];
    }
    if (parsedAgents.isNotEmpty) return parsedAgents;
  }

  // No explicit option, next we check for environment variables.
  final env =
      Platform.environment['SKILLS_AGENT'] ??
      // Legacy fallback
      Platform.environment['SKILLS_IDE'];
  if (env != null) {
    final agent = Agent.fromCliName(env);
    if (agent != null && agent != Agent.custom) return [agent];
    throw UsageException(
      'Unknown AGENT "$agent". Valid values: ${Agent.validNames}',
      usage,
    );
  }

  // Finally, try to auto-detect agents.
  final detected = const AgentDetector().detectAll(projectPath);
  if (detected.isNotEmpty) return detected;

  if (dialogSupport case var dialogSupport?) {
    final selectableAgents = [
      for (var agent in Agent.values)
        if (agent != Agent.custom) agent,
    ];
    final options = [for (var agent in selectableAgents) agent.label];
    final result = await dialogSupport.showMultiSelectDialog(
      options,
      title: 'Unable to auto-detect agent. Please select one or more:',
    );
    if (result != null && result.isNotEmpty) {
      return result.map((e) => selectableAgents[e]).toList();
    }
  }
  throw UsageException(
    'Could not auto-detect agent and none selected. Use --agent to specify one of: '
    '${Agent.validNames}',
    usage,
  );
}
