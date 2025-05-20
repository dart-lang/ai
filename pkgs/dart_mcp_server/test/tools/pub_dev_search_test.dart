// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:dart_mcp_server/src/mixins/pub_dev_search.dart';
import 'package:http/http.dart';
import 'package:test/test.dart';

import '../test_harness.dart';

void main() {
  Future<void> runWithHarness(
    Future<void> Function(TestHarness harness, Tool pubDevSearchTool) fn,
  ) async {
    final testHarness = await TestHarness.start(inProcess: true);
    final testRoot = testHarness.rootForPath(counterAppPath);
    testHarness.mcpClient.addRoot(testRoot);
    await pumpEventQueue();

    final tools = (await testHarness.mcpServerConnection.listTools()).tools;
    await fn(
      testHarness,
      tools.singleWhere((t) => t.name == PubDevSupport.pubDevTool.name),
    );
  }

  test('searches pub dev, and gathers information about packages', () async {
    await runWithClient(() async {
      await runWithHarness((testHarness, pubDevSearchTool) async {
        final request = CallToolRequest(
          name: pubDevSearchTool.name,
          arguments: {'query': 'retry', 'latestVersion': '3.1.2'},
        );

        final result = await testHarness.callToolWithRetry(
          request,
          maxTries: 1,
        );
        expect(result.content.length, 10);
        expect(
          result.content
              .map(
                (c) =>
                    (json.decode((c as TextContent).text)
                        as Map)['packageName'],
              )
              .toList(),
          [
            'retry',
            'http_client_helper',
            'dio_smart_retry',
            'en_file_uploader',
            'dio_retry_plus',
            'futuristic',
            'http_file_uploader',
            'dio_file_uploader',
            'network_checker',
            'buxing',
          ],
        );
        expect(json.decode((result.content[0] as TextContent).text), {
          'packageName': 'retry',
          'latestVersion': '3.1.2',
          'description':
              'Utility for wrapping an asynchronous function in automatic '
              'retry logic with exponential back-off, useful when making '
              'requests over network.',
          'scores': {
            'pubPoints': isA<int>(),
            'maxPubPoints': isA<int>(),
            'likes': isA<int>(),
            'downloadCount': isA<int>(),
          },
          'topics': ['topic:network', 'topic:http'],
          'licenses': [
            'license:apache-2.0',
            'license:fsf-libre',
            'license:osi-approved',
          ],
          'publisher': 'publisher:google.dev',
          'api': {
            'qualifiedNames': containsAll(['retry', 'retry.RetryOptions']),
          },
        });
      });
    }, _GoldenResponseClient.new);
  });

  test('Reports failure on missing response', () async {
    await runWithClient(() async {
      await runWithHarness((testHarness, pubDevSearchTool) async {
        final request = CallToolRequest(
          name: pubDevSearchTool.name,
          arguments: {'query': 'retry'},
        );

        final result = await testHarness.callToolWithRetry(
          request,
          maxTries: 1,
          expectError: true,
        );
        expect(result.isError, isTrue);
        expect(
          (result.content[0] as TextContent).text,
          contains('Failed searching pub.dev: ClientException: No internet'),
        );
      });
    }, () => _FixedResponseClient.withMappedResponses({}));
  });

  test('Tolerates missing sub-responses', () async {
    await runWithClient(
      () async {
        await runWithHarness((testHarness, pubDevSearchTool) async {
          final request = CallToolRequest(
            name: pubDevSearchTool.name,
            arguments: {'query': 'retry'},
          );

          final result = await testHarness.callToolWithRetry(
            request,
            maxTries: 1,
            expectError: true,
          );
          expect(result.content.length, 1);
          expect(json.decode((result.content[0] as TextContent).text), {
            'packageName': 'retry',
          });
        });
      },
      // Serve a single package as search result, but provide no further
      // information about it.
      () => _FixedResponseClient.withMappedResponses({
        'https://pub.dev/api/search?q=retry': jsonEncode({
          'packages': [
            {'package': 'retry'},
          ],
        }),
      }),
    );
  });

  test('No matching packages gets reported as an error', () async {
    await runWithClient(
      () async {
        await runWithHarness((testHarness, pubDevSearchTool) async {
          final request = CallToolRequest(
            name: pubDevSearchTool.name,
            arguments: {'query': 'retry'},
          );

          final result = await testHarness.callToolWithRetry(
            request,
            maxTries: 1,
            expectError: true,
          );
          expect(result.isError, isTrue);
          expect(
            (result.content[0] as TextContent).text,
            contains('No packages mached the query, consider simplifying it'),
          );
        });
      },
      // Serve no packages, but provide no further information
      // about it.
      () => _FixedResponseClient.withMappedResponses({
        'https://pub.dev/api/search?q=retry': jsonEncode({
          'packages': <Object?>[],
        }),
      }),
    );
  });
}

class _FixedResponseClient implements Client {
  final String Function(Uri url) handler;

  _FixedResponseClient(this.handler);

  _FixedResponseClient.withMappedResponses(Map<String, String> responses)
    : handler =
          ((url) =>
              responses[url.toString()] ??
              (throw ClientException('No internet')));

  @override
  Future<String> read(Uri url, {Map<String, String>? headers}) async {
    return handler(url);
  }

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw StateError('Unexpected call $invocation');
  }
}

class _GoldenResponseClient implements Client {
  _GoldenResponseClient();
  @override
  Future<String> read(Uri url, {Map<String, String>? headers}) async {
    return await _goldenResponse(url);
  }

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw StateError('Unexpected call $invocation');
  }
}

Future<String> _goldenResponse(Uri url) async {
  final goldenFile = File(
    'test_fixtures/pub_dev_responses/${Uri.encodeComponent(url.toString())}',
  );
  final String contents;
  final recreate = Platform.environment['RECREATE_GOLDEN_RESPONSES'];
  if (recreate == 'all' || recreate == 'missing' && !goldenFile.existsSync()) {
    final client = Client();
    final rawContents = await client.read(url);
    // For readability we format the json response.
    contents = const JsonEncoder.withIndent(
      '  ',
    ).convert(jsonDecode(rawContents));
    client.close();
    goldenFile.createSync(recursive: true);
    goldenFile.writeAsStringSync(contents);
    return contents;
  } else {
    try {
      return goldenFile.readAsStringSync();
    } on IOException catch (e) {
      fail(
        'Could not read golden response file ${goldenFile.path} for $url: $e. '
        'Consider recreating by calling with '
        '\$RECREATE_GOLDEN_RESPONSES=missing',
      );
    }
  }
}
