import 'package:skills/src/ide/ide.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  group('Given a project with a .cursor directory', () {
    test('when detecting IDE then returns cursor', () async {
      await d.dir('cursor_project', [d.dir('.cursor')]).create();

      const detector = IdeDetector();
      final ide = detector.detect(d.path('cursor_project'));

      expect(ide, equals(Ide.cursor));
    });
  });

  group('Given a project with a .agent directory', () {
    test('when detecting IDE then returns generic', () async {
      await d.dir('ag_project', [d.dir('.agent')]).create();

      const detector = IdeDetector();
      final ide = detector.detect(d.path('ag_project'));

      expect(ide, equals(Ide.generic));
    });
  });

  group('Given a project with a .claude directory', () {
    test('when detecting IDE then returns claude', () async {
      await d.dir('claude_project', [d.dir('.claude')]).create();

      const detector = IdeDetector();
      final ide = detector.detect(d.path('claude_project'));

      expect(ide, equals(Ide.claude));
    });
  });

  group('Given a project with a .clinerules directory', () {
    test('when detecting IDE then returns cline', () async {
      await d.dir('cline_project', [d.dir('.clinerules')]).create();

      const detector = IdeDetector();
      final ide = detector.detect(d.path('cline_project'));

      expect(ide, equals(Ide.cline));
    });
  });

  group('Given a project with a .opencode directory', () {
    test('when detecting IDE then returns opencode', () async {
      await d.dir('opencode_project', [d.dir('.opencode')]).create();

      const detector = IdeDetector();
      final ide = detector.detect(d.path('opencode_project'));

      expect(ide, equals(Ide.opencode));
    });
  });

  group('Given a project with .github/copilot-instructions.md', () {
    test('when detecting IDE then does not auto-detect copilot', () async {
      await d.dir('copilot_project', [
        d.dir('.github', [d.file('copilot-instructions.md', '# Instructions')]),
      ]).create();

      const detector = IdeDetector();
      final ide = detector.detect(d.path('copilot_project'));

      expect(ide, isNull);
    });

    test('when using fromCliName then copilot is still available', () {
      expect(Ide.fromCliName('copilot'), equals(Ide.copilot));
    });
  });

  group('Given a project with no IDE markers', () {
    test('when detecting IDE then returns null', () async {
      await d.dir('bare_project').create();

      const detector = IdeDetector();
      final ide = detector.detect(d.path('bare_project'));

      expect(ide, isNull);
    });

    test('when detecting all IDEs then returns empty list', () async {
      await d.dir('bare_project2').create();

      const detector = IdeDetector();
      final ides = detector.detectAll(d.path('bare_project2'));

      expect(ides, isEmpty);
    });
  });

  group('Given a project with multiple IDE markers', () {
    test('when detecting single IDE then returns null', () async {
      await d.dir('multi_ide_project', [
        d.dir('.cursor'),
        d.dir('.agent'),
      ]).create();

      const detector = IdeDetector();
      final ide = detector.detect(d.path('multi_ide_project'));

      expect(ide, isNull);
    });

    test('when detecting all IDEs then returns all detected', () async {
      await d.dir('multi_ide_project2', [
        d.dir('.cursor'),
        d.dir('.agent'),
        d.dir('.claude'),
      ]).create();

      const detector = IdeDetector();
      final ides = detector.detectAll(d.path('multi_ide_project2'));

      expect(ides, hasLength(3));
      expect(ides, containsAll([Ide.cursor, Ide.generic, Ide.claude]));
    });
  });

  group('Given Ide.fromCliName', () {
    test('when given valid name then returns correct enum', () {
      expect(Ide.fromCliName('cursor'), equals(Ide.cursor));
      expect(Ide.fromCliName('generic'), equals(Ide.generic));
      expect(Ide.fromCliName('claude'), equals(Ide.claude));
      expect(Ide.fromCliName('copilot'), equals(Ide.copilot));
      expect(Ide.fromCliName('cline'), equals(Ide.cline));
      expect(Ide.fromCliName('opencode'), equals(Ide.opencode));
    });

    test('when given generic aliases then returns generic', () {
      expect(Ide.fromCliName('antigravity'), equals(Ide.generic));
      expect(Ide.fromCliName('codex'), equals(Ide.generic));
    });

    test('when given invalid name then returns null', () {
      expect(Ide.fromCliName('vim'), isNull);
      expect(Ide.fromCliName(''), isNull);
    });

    test('when given mixed case then still matches', () {
      expect(Ide.fromCliName('Cursor'), equals(Ide.cursor));
      expect(Ide.fromCliName('CLINE'), equals(Ide.cline));
    });
  });
}
