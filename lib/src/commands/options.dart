import 'dart:io' show Platform;

import 'package:args/args.dart';
import 'package:config/config.dart';

import '../ide/ide.dart';

/// Parses the --ide option from [argResults].
/// Returns the IDE if --ide was specified, or null if not.
/// Throws [UsageException] if --ide was specified but invalid.
Ide? parseIdeOption(ArgResults? argResults) {
  final ideStr = argResults?['ide'] as String?;
  if (ideStr == null) return null;
  final ide = Ide.fromCliName(ideStr);
  if (ide != null) return ide;
  throw UsageException(
    'Unknown IDE "$ideStr". Valid values: ${Ide.validNames}',
    '',
  );
}

/// Shared option definitions for the CLI commands.
enum SkillsOption<V> implements OptionDefinition<V> {
  ide(
    StringOption(argName: 'ide', envName: 'SKILLS_IDE', helpText: 'Target IDE'),
  );

  const SkillsOption(this.option);

  @override
  final ConfigOptionBase<V> option;
}

/// Registers the shared `--ide` option on [argParser].
void addIdeOption(ArgParser argParser) {
  argParser.addOption('ide', help: 'Target IDE', allowed: Ide.cliNames);
}

/// Returns the IDEs to operate on.
///
/// If `--ide` is specified (or the `SKILLS_IDE` env var), returns that single
/// IDE. Otherwise returns all auto-detected IDEs.
/// Throws if no IDE can be determined.
List<Ide> resolveIdes({
  required ArgResults? argResults,
  required String projectPath,
}) {
  final config = Configuration.resolveNoExcept(
    options: SkillsOption.values,
    argResults: argResults,
    env: Platform.environment,
  );

  final ideStr = config.optionalValue(SkillsOption.ide);
  if (ideStr != null) {
    final ide = Ide.fromCliName(ideStr);
    if (ide != null) return [ide];
    throw UsageException(
      'Unknown IDE "$ideStr". Valid values: ${Ide.validNames}',
      '',
    );
  }

  final detected = const IdeDetector().detectAll(projectPath);
  if (detected.isEmpty) {
    throw UsageException(
      'Could not auto-detect IDE. Use --ide to specify one of: ${Ide.validNames}',
      '',
    );
  }
  return detected;
}
