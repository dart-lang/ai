// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dart_mcp/server.dart';
import 'package:dart_mcp_server/src/utils/analytics.dart';
import 'package:test/test.dart';
import 'package:unified_analytics/testing.dart';

void main() {
  group('sanitizeForAnalytics', () {
    test('does not change normal values', () {
      for (final value in [
        'Visual Studio Code',
        'claude-code',
        'gemini-cli-mcp-client',
        'test client for the dart tooling mcp server',
        '1.2.3-beta.1+build.5',
      ]) {
        expect(sanitizeForAnalytics(value), value);
      }
    });

    test('removes string interpolations', () {
      expect(sanitizeForAnalytics(r'client${name}'), 'client');
      expect(sanitizeForAnalytics(r'${a} client ${b}'), 'client');
      expect(sanitizeForAnalytics(r'client ${unterminated'), 'client');
    });

    test('never leaves a string interpolation behind', () {
      expect(sanitizeForAnalytics(r'$${a}{b}'), '{b}');
      expect(sanitizeForAnalytics(r'${${a}}'), '}');
      expect(sanitizeForAnalytics(r'US$5'), 'US5');
    });

    test('replaces control characters and trims whitespace', () {
      expect(
        sanitizeForAnalytics('  my\nclient\r\n\tname\x00 '),
        'my client name',
      );
      expect(sanitizeForAnalytics('my\x7Fclient'), 'my client');
      expect(sanitizeForAnalytics('my\u2028client'), 'my client');
    });

    test('truncates long values', () {
      expect(
        sanitizeForAnalytics('a' * (maxSanitizedAnalyticsValueLength + 10)),
        'a' * maxSanitizedAnalyticsValueLength,
      );
    });

    test('does not split surrogate pairs when truncating', () {
      final sanitized = sanitizeForAnalytics(
        '\u{1F600}' * (maxSanitizedAnalyticsValueLength + 1),
      );
      expect(sanitized.runes, hasLength(maxSanitizedAnalyticsValueLength));
      expect(sanitized.runes, everyElement(0x1F600));
    });
  });

  group('createDartMCPEvent', () {
    test('sanitizes the values that come from outside of the server', () {
      final event = withAgentPluginOverride(
        r'dart-${oops}flutter',
        () => createDartMCPEvent(
          clientInfo: Implementation(
            name: r'my-client${evil}',
            version: '1.0.0\n',
          ),
          serverInfo: Implementation(name: 'server', version: '2.0.0'),
          type: AnalyticsEvent.listTools.name,
        ),
      );
      expect(event.eventName, DashEvent.dartMCPEvent);
      expect(event.eventData, {
        'client': 'my-client',
        'clientVersion': '1.0.0',
        'serverVersion': '2.0.0',
        'type': AnalyticsEvent.listTools.name,
        'agentPlugin': 'dart-flutter',
      });
    });
  });
}
