import 'package:args/command_runner.dart';
import 'package:skills/src/commands/get_command.dart';
import 'package:skills/src/commands/list_command.dart';
import 'package:skills/src/commands/remove_command.dart';

Future<void> main(List<String> arguments) async {
  final runner =
      CommandRunner<void>(
          'skills',
          'Manage AI agent skills for Dart/Flutter packages.',
        )
        ..addCommand(GetCommand())
        ..addCommand(RemoveCommand())
        ..addCommand(ListCommand());

  try {
    await runner.run(arguments);
  } on UsageException catch (e) {
    print(e);
  }
}
