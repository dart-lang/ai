import 'package:logging/logging.dart';
import 'package:skills/src/agent/agent.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  setUpAll(() {
    Logger.root.onRecord.listen((r) => printOnFailure(r.toString()));
  });

  group('Given a project with a .cursor directory', () {
    test('when detecting agent then returns cursor', () async {
      await d.dir('cursor_project', [d.dir('.cursor')]).create();

      const detector = AgentDetector();
      final agent = detector.detect(d.path('cursor_project'));

      expect(agent, equals(Agent.cursor));
    });
  });

  group('Given a project with a .agents directory', () {
    test('when detecting agent then returns generic', () async {
      await d.dir('ag_project', [d.dir('.agents')]).create();

      const detector = AgentDetector();
      final agent = detector.detect(d.path('ag_project'));

      expect(agent, equals(Agent.generic));
    });
  });

  group('Given a project with a .claude directory', () {
    test('when detecting agent then returns claude', () async {
      await d.dir('claude_project', [d.dir('.claude')]).create();

      const detector = AgentDetector();
      final agent = detector.detect(d.path('claude_project'));

      expect(agent, equals(Agent.claude));
    });
  });

  group('Given a project with a .clinerules directory', () {
    test('when detecting agent then returns cline', () async {
      await d.dir('cline_project', [d.dir('.clinerules')]).create();

      const detector = AgentDetector();
      final agent = detector.detect(d.path('cline_project'));

      expect(agent, equals(Agent.cline));
    });
  });

  group('Given a project with a .opencode directory', () {
    test('when detecting agent then returns opencode', () async {
      await d.dir('opencode_project', [d.dir('.opencode')]).create();

      const detector = AgentDetector();
      final agent = detector.detect(d.path('opencode_project'));

      expect(agent, equals(Agent.opencode));
    });
  });

  group('Given a project with .github/copilot-instructions.md', () {
    test('when detecting agent then does not auto-detect copilot', () async {
      await d.dir('copilot_project', [
        d.dir('.github', [d.file('copilot-instructions.md', '# Instructions')]),
      ]).create();

      const detector = AgentDetector();
      final agent = detector.detect(d.path('copilot_project'));

      expect(agent, isNull);
    });

    test('when using fromCliName then copilot is still available', () {
      expect(Agent.fromCliName('copilot'), equals(Agent.copilot));
    });
  });

  group('Given a project with no agent markers', () {
    test('when detecting agent then returns null', () async {
      await d.dir('bare_project').create();

      const detector = AgentDetector();
      final agent = detector.detect(d.path('bare_project'));

      expect(agent, isNull);
    });

    test('when detecting all agents then returns empty list', () async {
      await d.dir('bare_project2').create();

      const detector = AgentDetector();
      final agents = detector.detectAll(d.path('bare_project2'));

      expect(agents, isEmpty);
    });
  });

  group('Given a project with multiple agent markers', () {
    test('when detecting single agent then returns null', () async {
      await d.dir('multi_ide_project', [
        d.dir('.cursor'),
        d.dir('.agents'),
      ]).create();

      const detector = AgentDetector();
      final agent = detector.detect(d.path('multi_ide_project'));

      expect(agent, isNull);
    });

    test('when detecting all agents then returns all detected', () async {
      await d.dir('multi_ide_project2', [
        d.dir('.cursor'),
        d.dir('.agents'),
        d.dir('.claude'),
      ]).create();

      const detector = AgentDetector();
      final agents = detector.detectAll(d.path('multi_ide_project2'));

      expect(agents, hasLength(3));
      expect(agents, containsAll([Agent.cursor, Agent.generic, Agent.claude]));
    });
  });

  group('Given Agent.fromCliName', () {
    test('when given valid name then returns correct enum', () {
      expect(Agent.fromCliName('cursor'), equals(Agent.cursor));
      expect(Agent.fromCliName('generic'), equals(Agent.generic));
      expect(Agent.fromCliName('claude'), equals(Agent.claude));
      expect(Agent.fromCliName('copilot'), equals(Agent.copilot));
      expect(Agent.fromCliName('cline'), equals(Agent.cline));
      expect(Agent.fromCliName('opencode'), equals(Agent.opencode));
    });

    test('when given generic aliases then returns generic', () {
      expect(Agent.fromCliName('antigravity'), equals(Agent.generic));
      expect(Agent.fromCliName('codex'), equals(Agent.generic));
    });

    test('when given invalid name then returns null', () {
      expect(Agent.fromCliName('vim'), isNull);
      expect(Agent.fromCliName(''), isNull);
    });

    test('when given mixed case then still matches', () {
      expect(Agent.fromCliName('Cursor'), equals(Agent.cursor));
      expect(Agent.fromCliName('CLINE'), equals(Agent.cline));
    });
  });
}
