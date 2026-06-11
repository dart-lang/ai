import 'package:logging/logging.dart';
import 'package:skills/src/ide/adapters/cursor_adapter.dart';
import 'package:skills/src/ide/adapters/rules_adapter.dart';
import 'package:skills/src/ide/ide.dart';
import 'package:skills/src/ide/ide_adapter.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import '../fake_dialog_support.dart';

void main() {
  for (final adapterType in [CursorAdapter, RulesAdapter]) {
    group('$adapterType.removeSkill', () {
      group('given skills with manual edits during the update process', () {
        late IdeAdapter adapter;
        final skillName = 'pkg-skill';
        final originalSkillText =
            '---\nname: $skillName\ndescription: original description\n---\nOriginal text';
        final editedSkillText =
            '---\nname: $skillName\ndescription: edited description\n---\nEdited text';

        // The descriptor for the current [adapterType].
        //
        // Contains `content` if not null, otherwise it should not exist.
        d.Descriptor installedSkillDescriptor({required String? content}) =>
            d.dir('project', [
              d.dir('.cursor', [
                d.dir('skills', [
                  switch (adapterType) {
                    const (CursorAdapter) => switch (content) {
                        String _ =>
                          d.dir(skillName, [d.file('SKILL.md', content)]),
                        null => d.nothing('SKILL.md'),
                      },
                    const (RulesAdapter) => switch (content) {
                        String _ => d.file('$skillName.md', content),
                        null => d.nothing('$skillName.md'),
                      },
                    _ =>
                      throw StateError('Unexpected adapter type $adapterType'),
                  }
                ]),
              ]),
            ]);

        setUp(() async {
          await installedSkillDescriptor(content: originalSkillText).create();

          await d.dir('pkg_source', [
            d.dir('skills', [
              d.dir(skillName, [
                d.file('SKILL.md', editedSkillText),
              ]),
            ]),
          ]).create();
        });

        group('with dialog support', () {
          late FakeDialogSupport fakeDialog;
          setUp(() {
            fakeDialog = FakeDialogSupport();

            adapter = switch (adapterType) {
              const (CursorAdapter) =>
                CursorAdapter(d.path('project'), dialogSupport: fakeDialog),
              const (RulesAdapter) => RulesAdapter(
                  skillsDirectory: Ide.cursor.skillsPath(d.path('project')),
                  dialogSupport: fakeDialog,
                ),
              _ => throw StateError('unexpected adapter type'),
            };
          });

          test('when the user chooses not to overwrite the skill', () async {
            // User selects "No" (index 1 is No)
            fakeDialog.singleSelectResults = [1];
            final result = await adapter.removeSkill(
              skillName,
              originalHash: 'some-original-hash',
            );

            expect(fakeDialog.singleSelectCallCount, 1,
                reason: 'then it should prompt the user');
            expect(result, isFalse, reason: 'then it should return false');
            await installedSkillDescriptor(content: originalSkillText)
                .validate();
          });

          test('when the user chooses to overwrite the skill', () async {
            // User selects "Yes" (index 0 is Yes)
            fakeDialog.singleSelectResults = [0];
            final result = await adapter.removeSkill(
              skillName,
              originalHash: 'some-original-hash',
            );

            expect(fakeDialog.singleSelectCallCount, 1,
                reason: 'then it should prompt the user');
            expect(result, isTrue, reason: 'then it should return true');
            await installedSkillDescriptor(content: null).validate();
          });

          test('when force is true', () async {
            final result = await adapter.removeSkill(
              skillName,
              originalHash: 'some-original-hash',
              force: true,
            );

            expect(result, isTrue, reason: 'then should return true');
            expect(fakeDialog.singleSelectCallCount, 0,
                reason: 'then should not prompt the user');

            await installedSkillDescriptor(content: null).validate();
          });
        });

        group('without dialog support', () {
          setUp(() {
            adapter = switch (adapterType) {
              const (CursorAdapter) => CursorAdapter(d.path('project')),
              const (RulesAdapter) => RulesAdapter(
                  skillsDirectory: Ide.cursor.skillsPath(d.path('project')),
                ),
              _ => throw StateError('unexpected adapter type'),
            };
          });

          test('then logs suggesting the use of --force', () async {
            final logs = <LogRecord>[];
            final listener = adapter.logger.onRecord.listen(logs.add);
            final result = await adapter.removeSkill(
              skillName,
              originalHash: 'some-original-hash',
            );
            await listener.cancel();

            expect(result, isFalse, reason: 'then it should return false');
            await installedSkillDescriptor(content: originalSkillText)
                .validate();
            expect(
                logs,
                contains(isA<LogRecord>().having(
                    (r) => r.message,
                    'message',
                    allOf(contains('Skipped upgrading pkg-skill'),
                        contains('Re-run with `--force`')))));
          });
        });
      });
    });
  }
}
