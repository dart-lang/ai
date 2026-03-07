import 'package:skills/src/core/git_runner.dart';
import 'package:test/test.dart';

void main() {
  group('GitRunner', () {
    test('when override returns false then isAvailable is false', () async {
      const runner = GitRunner(isAvailableOverride: _returnFalse);
      expect(await runner.isAvailable, isFalse);
    });

    test('when override returns true then isAvailable is true', () async {
      const runner = GitRunner(isAvailableOverride: _returnTrue);
      expect(await runner.isAvailable, isTrue);
    });
  });
}

Future<bool> _returnFalse() async => false;
Future<bool> _returnTrue() async => true;
