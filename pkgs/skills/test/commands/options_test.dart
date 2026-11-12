import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:skills/src/commands/options.dart';
import 'package:skills/src/agent/agent.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import '../fake_dialog_support.dart';

void main() {
  group('Given a basic project when resolveAgents is called', () {
    late String projectPath;
    late FakeDialogSupport fakeDialogSupport;

    setUp(() async {
      await d.dir('project').create();
      projectPath = d.path('project');
      fakeDialogSupport = FakeDialogSupport();
    });

    test(
      'and --agent is specified then it returns the specified agent',
      () async {
        final parser = ArgParser();
        addAgentOption(parser);
        addInstallDirOption(parser);
        final argResults = parser.parse(['--agent', 'cursor']);

        final agents = await resolveAgents(
          argResults: argResults,
          projectPath: projectPath,
          dialogSupport: fakeDialogSupport,
        );

        expect(agents, equals([Agent.cursor]));
      },
    );

    test(
      'and --install-dir is specified then it returns an agent for that directory',
      () async {
        final parser = ArgParser();
        addAgentOption(parser);
        addInstallDirOption(parser);
        final argResults = parser.parse(['--install-dir', 'custom_dir']);

        final agents = await resolveAgents(
          argResults: argResults,
          projectPath: projectPath,
          dialogSupport: fakeDialogSupport,
        );

        expect(agents.map((a) => a.cliName), equals(['dir:custom_dir']));
      },
    );

    test(
      'and -d is specified then it returns an agent for that directory',
      () async {
        final parser = ArgParser();
        addAgentOption(parser);
        addInstallDirOption(parser);
        final argResults = parser.parse(['-d', 'custom_dir']);

        final agents = await resolveAgents(
          argResults: argResults,
          projectPath: projectPath,
          dialogSupport: fakeDialogSupport,
        );

        expect(agents.map((a) => a.cliName), equals(['dir:custom_dir']));
      },
    );

    test(
      'and both --agent and --install-dir are used then it returns both agents',
      () async {
        final parser = ArgParser();
        addAgentOption(parser);
        addInstallDirOption(parser);
        final argResults = parser.parse([
          '--agent',
          'cursor',
          '--install-dir',
          'custom_dir',
        ]);

        final agents = await resolveAgents(
          argResults: argResults,
          projectPath: projectPath,
          dialogSupport: fakeDialogSupport,
        );

        expect(
          agents.map((a) => a.cliName),
          equals(['cursor', 'dir:custom_dir']),
        );
      },
    );

    test('and --install-dir is empty then it throws UsageException', () async {
      final parser = ArgParser();
      addAgentOption(parser);
      addInstallDirOption(parser);
      final argResults = parser.parse(['--install-dir', '   ']);

      expect(
        () => resolveAgents(
          argResults: argResults,
          projectPath: projectPath,
          dialogSupport: fakeDialogSupport,
        ),
        throwsA(
          isA<UsageException>().having(
            (e) => e.message,
            'message',
            contains('--install-dir requires a non-empty path'),
          ),
        ),
      );
    });

    test('SKILLS_AGENT=dir:custom_dir throws UsageException', () async {
      expect(
        () => resolveAgents(
          argResults: null,
          projectPath: projectPath,
          dialogSupport: fakeDialogSupport,
          environment: {'SKILLS_AGENT': 'dir:custom_dir'},
        ),
        throwsA(
          isA<UsageException>().having(
            (e) => e.message,
            'message',
            contains('Unknown AGENT "dir:custom_dir"'),
          ),
        ),
      );
    });

    test(
      'and auto-detection succeeds then it returns the detected agents',
      () async {
        await d.dir('project', [d.dir('.cursor')]).create();

        final agents = await resolveAgents(
          argResults: null,
          projectPath: projectPath,
          dialogSupport: fakeDialogSupport,
        );

        expect(agents, equals([Agent.cursor]));
      },
    );

    group('and auto-detection fails', () {
      test(
        'and the user selects an agent in the dialog then it returns the selected agent',
        () async {
          fakeDialogSupport.multiSelectResults.add({1});

          final agents = await resolveAgents(
            argResults: null,
            projectPath: projectPath,
            dialogSupport: fakeDialogSupport,
          );

          expect(agents, equals([Agent.values[1]]));
        },
      );

      test(
        'and the user selects nothing in the dialog then it throws UsageException',
        () async {
          fakeDialogSupport.multiSelectResults.add({});

          expect(
            () => resolveAgents(
              argResults: null,
              projectPath: projectPath,
              dialogSupport: fakeDialogSupport,
            ),
            throwsA(isA<UsageException>()),
          );
        },
      );

      test(
        'and dialog support is missing then it throws UsageException',
        () async {
          expect(
            () => resolveAgents(
              argResults: null,
              projectPath: projectPath,
              dialogSupport: null,
            ),
            throwsA(isA<UsageException>()),
          );
        },
      );
    });
  });
}
