import 'dart:io' show Platform;

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:skills/src/core/dialog_support.dart';

import '../agent/agent.dart';

/// Parses the --agent option from [argResults].
/// Returns the agents that were specified via --agent.
List<Agent> parseAgentOption(ArgResults argResults) {
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

/// Returns the agents to operate on.
///
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
}) async {
  final parsedAgents = argResults == null
      ? <Agent>[]
      : parseAgentOption(argResults);
  if (parsedAgents.isNotEmpty) return parsedAgents;

  // No explicit option, next we check for environment variables.
  final env =
      Platform.environment['SKILLS_AGENT'] ??
      // Legacy fallback
      Platform.environment['SKILLS_IDE'];
  if (env != null) {
    final agent = Agent.fromCliName(env);
    if (agent != null) return [agent];
    throw UsageException(
      'Unknown AGENT "$agent". Valid values: ${Agent.validNames}',
      '',
    );
  }

  // Finally, try to auto-detect agents.
  final detected = const AgentDetector().detectAll(projectPath);
  if (detected.isNotEmpty) return detected;

  if (dialogSupport case var dialogSupport?) {
    final options = Agent.values.map((e) => e.cliName).toList();
    final result = await dialogSupport.showMultiSelectDialog(
      options,
      title: 'Unable to auto-detect agent. Please select one or more:',
    );
    if (result != null && result.isNotEmpty) {
      return result.map((e) => Agent.values[e]).toList();
    }
  }
  throw UsageException(
    'Could not auto-detect agent and none selected. Use --agent to specify one of: '
        '${Agent.validNames}',
    '',
  );
}
