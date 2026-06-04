import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:skills/src/commands/options.dart';
import 'package:skills/src/ide/ide.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import '../fake_dialog_support.dart';

void main() {
  group('Given a basic project when resolveIdes is called', () {
    late String projectPath;
    late FakeDialogSupport fakeDialogSupport;

    setUp(() async {
      await d.dir('project').create();
      projectPath = d.path('project');
      fakeDialogSupport = FakeDialogSupport();
    });

    test('and --ide is specified then it returns the specified IDE', () async {
      final parser = ArgParser()..addOption('ide');
      final argResults = parser.parse(['--ide', 'cursor']);

      final ides = await resolveIdes(
        argResults: argResults,
        projectPath: projectPath,
        dialogSupport: fakeDialogSupport,
      );

      expect(
        ides,
        equals([Ide.cursor]),
      );
    });

    test('and auto-detection succeeds then it returns the detected IDEs',
        () async {
      await d.dir('project', [
        d.dir('.cursor'),
      ]).create();

      final ides = await resolveIdes(
        argResults: null,
        projectPath: projectPath,
        dialogSupport: fakeDialogSupport,
      );

      expect(
        ides,
        equals([Ide.cursor]),
      );
    });

    group('and auto-detection fails', () {
      test(
          'and the user selects an IDE in the dialog then it returns the selected IDE',
          () async {
        fakeDialogSupport.multiSelectResults.add({1});

        final ides = await resolveIdes(
          argResults: null,
          projectPath: projectPath,
          dialogSupport: fakeDialogSupport,
        );

        expect(
          ides,
          equals([Ide.values[1]]),
        );
      });

      test(
          'and the user selects nothing in the dialog then it throws UsageException',
          () async {
        fakeDialogSupport.multiSelectResults.add({});

        expect(
          () => resolveIdes(
            argResults: null,
            projectPath: projectPath,
            dialogSupport: fakeDialogSupport,
          ),
          throwsA(isA<UsageException>()),
        );
      });

      test('and dialog support is missing then it throws UsageException',
          () async {
        expect(
          () => resolveIdes(
            argResults: null,
            projectPath: projectPath,
            dialogSupport: null,
          ),
          throwsA(isA<UsageException>()),
        );
      });
    });
  });
}
