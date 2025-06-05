// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:dart_mcp/server.dart';
import 'package:http/http.dart';
import 'package:pool/pool.dart';

import '../utils/json.dart';

/// Limit the number of concurrent requests.
final _pool = Pool(10);

/// The number of results to return for a query.
// If this should be set higher than 10 we need to implement paging of the
// http://pub.dev/api/search endpoint.
final _resultsLimit = 10;

/// Mix this in to any MCPServer to add support for doing searches on pub.dev.
base mixin PubDevSupport on ToolsSupport {
  final _client = Client();

  @override
  FutureOr<InitializeResult> initialize(InitializeRequest request) {
    registerTool(pubDevTool, _runPubDevSearch);
    return super.initialize(request);
  }

  /// Implementation of the [pubDevTool].
  Future<CallToolResult> _runPubDevSearch(CallToolRequest request) async {
    final query = request.arguments?['query'] as String?;
    if (query == null) {
      return CallToolResult(
        content: [TextContent(text: 'Missing required argument `query`.')],
        isError: true,
      );
    }
    final searchUrl = Uri.https('pub.dev', 'api/search', {'q': query});
    final Object? result;
    try {
      result = jsonDecode(await _client.read(searchUrl));

      final packageNames = dig<List>(result, [
        'packages',
      ]).take(_resultsLimit).map((p) => dig<String>(p, ['package'])).toList();

      if (packageNames.isEmpty) {
        return CallToolResult(
          content: [
            TextContent(
              text: 'No packages matched the query, consider simplifying it.',
            ),
          ],
          isError: true,
        );
      }

      Future<Object?> retrieve(String path) {
        return _pool.withResource(() async {
          try {
            return jsonDecode(await _client.read(Uri.https('pub.dev', path)));
          } on ClientException {
            return null;
          }
        });
      }

      // Retrieve information about all the packages in parallel.
      final subQueryFutures = packageNames
          .map(
            (packageName) => (
              versionListing: retrieve('api/packages/$packageName'),
              score: retrieve('api/packages/$packageName/score'),
              docIndex: retrieve(
                'documentation/$packageName/latest/index.json',
              ),
            ),
          )
          .toList();

      // Aggregate the retrieved information about each package into a
      // TextContent.
      final results = <TextContent>[];
      for (var i = 0; i < packageNames.length; i++) {
        final packageName = packageNames[i];
        final versionListing = await subQueryFutures[i].versionListing;
        final scoreResult = await subQueryFutures[i].score;
        final libraryDocs = {
          for (var object
              in ((await subQueryFutures[i].docIndex) as List?)
                      ?.cast<Map<String, Object?>>() ??
                  <Map<String, Object?>>[])
            if (!object.containsKey('enclosedBy'))
              object['name'] as String: Uri.https(
                'pub.dev',
                'documentation/$packageName/latest/${object['href']}',
              ).toString(),
        };
        results.add(
          TextContent(
            text: jsonEncode({
              'packageName': packageName,
              if (versionListing != null) ...{
                'latestVersion': dig<String>(versionListing, [
                  'latest',
                  'version',
                ]),
                'description': ?dig<String?>(versionListing, [
                  'latest',
                  'pubspec',
                  'description',
                ]),
                'homepage': ?dig<String?>(versionListing, [
                  'latest',
                  'pubspec',
                  'homepage',
                ]),
                'repository': ?dig<String?>(versionListing, [
                  'latest',
                  'pubspec',
                  'repository',
                ]),
                'documentation': ?dig<String?>(versionListing, [
                  'latest',
                  'pubspec',
                  'documentation',
                ]),
              },
              if (libraryDocs.isNotEmpty) ...{'libraries': libraryDocs},
              if (scoreResult != null) ...{
                'scores': {
                  'pubPoints': dig<int>(scoreResult, ['grantedPoints']),
                  'maxPubPoints': dig<int>(scoreResult, ['maxPoints']),
                  'likes': dig<int>(scoreResult, ['likeCount']),
                  'downloadCount': dig<int>(scoreResult, [
                    'downloadCount30Days',
                  ]),
                },
                'topics': dig<List>(scoreResult, [
                  'tags',
                ]).where((t) => (t as String).startsWith('topic:')).toList(),
                'licenses': dig<List>(scoreResult, [
                  'tags',
                ]).where((t) => (t as String).startsWith('license')).toList(),
                'publisher': dig<List>(scoreResult, ['tags'])
                    .where((t) => (t as String).startsWith('publisher:'))
                    .firstOrNull,
              },
            }),
          ),
        );
      }

      return CallToolResult(content: results);
    } on Exception catch (e) {
      return CallToolResult(
        content: [TextContent(text: 'Failed searching pub.dev: $e')],
        isError: true,
      );
    }
  }

  static final pubDevTool = Tool(
    name: 'pub_dev_search',
    description:
        'Searches pub.dev for packages relevant to a given search query. '
        'The response will describe each result with its download count, '
        'package description, topics, license, and publisher.',
    annotations: ToolAnnotations(title: 'pub.dev search', readOnlyHint: true),
    inputSchema: Schema.object(
      properties: {
        'query': Schema.string(
          title: 'Search query',
          description: '''
The query to run against pub.dev package search.

Besides freeform keyword search `pub.dev` supports the following search query
expressions:

  - `"exact phrase"`: By default, when you perform a search, the results include
    packages with similar phrases. When a phrase is inside quotes, you'll see
    only those packages that contain exactly the specified phrase.

  - `dependency:<package_name>`: Searches for packages that reference
    `package_name` in their `pubspec.yaml`.

  - `dependency*:<package_name>`: Searches for packages that depend on
    `package_name` (as direct, dev, or transitive dependencies).

  - `topic:<topic-name>`: Searches for packages that have specified the
    `topic-name` [topic](/topics).

  - `publisher:<publisher-name.com>`: Searches for packages published by `publisher-name.com`

  - `sdk:<sdk>`: Searches for packages that support the given SDK. `sdk` can be either `flutter` or `dart`

  - `runtime:<runtime>`: Searches for packages that support the given runtime. `runtime` can be one of `web`, `native-jit` and `native-aot`.

  - `updated:<duration>`: Searches for packages updated in the given past days,
    with the following recognized formats: `3d` (3 days), `2w` (two weeks), `6m` (6 months), `2y` 2 years.

  - `has:executable`: Search for packages with Dart files in their `bin/` directory.

To search for alternatives do multiple searches. There is no "or" operator.
  ''',
        ),
      },
      required: ['query'],
    ),
  );
}
