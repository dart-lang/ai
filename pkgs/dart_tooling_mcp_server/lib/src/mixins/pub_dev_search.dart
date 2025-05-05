// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:dart_mcp/server.dart';
import 'package:http/http.dart';

/// Mix this in to any MCPServer to add support for doing searches on pub.dev.
base mixin PubDevSupport on ToolsSupport {
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
        content: [
          TextContent(text: 'Missing required argument `search-query`.'),
        ],
        isError: true,
      );
    }
    final client = Client();
    final searchUrl = Uri(
      scheme: 'https',
      host: 'pub.dev',
      path: 'api/search',
      queryParameters: {'q': query},
    );
    final Object? result;
    try {
      result = jsonDecode(await client.read(searchUrl));

      final packages = dig<List>(result, ['packages']);

      final results = <TextContent>[];
      for (final i in (packages as Iterable).take(10)) {
        final packageName = dig<String>(i, ['package']);
        final packageListing = jsonDecode(
          await client.read(
            Uri(
              scheme: 'https',
              host: 'pub.dev',
              path: 'api/packages/$packageName',
              queryParameters: {'q': query},
            ),
          ),
        );

        final latestVersion = dig<String>(packageListing, [
          'latest',
          'version',
        ]);
        final description = dig<String>(packageListing, [
          'latest',
          'pubspec',
          'description',
        ]);
        final scoreResult = jsonDecode(
          await client.read(
            Uri(
              scheme: 'https',
              host: 'pub.dev',
              path: 'api/packages/$packageName/score',
              queryParameters: {'q': query},
            ),
          ),
        );
        final scores = {
          'pubPoints': dig<int>(scoreResult, ['grantedPoints']),
          'maxPubPoints': dig<int>(scoreResult, ['maxPoints']),
          'likes': dig<int>(scoreResult, ['likeCount']),
          'downloadCount': dig<int>(scoreResult, ['downloadCount30Days']),
        };
        final topics =
            dig<List>(scoreResult, [
              'tags',
            ]).where((t) => (t as String).startsWith('topic:')).toList();
        final licenses =
            dig<List>(scoreResult, [
              'tags',
            ]).where((t) => (t as String).startsWith('license')).toList();
        final index = jsonDecode(
          await client.read(
            Uri(
              scheme: 'https',
              host: 'pub.dev',
              path: 'documentation/$packageName/latest/index.json',
            ),
          ),
        );
        final items = dig<List>(index, []);
        final identifiers = <Map<String, Object?>>[];
        for (final item in items) {
          identifiers.add({
            'qualifiedName': dig(item, ['qualifiedName']),
            'desc': 'Object holding options for retrying a function.',
          });
        }
        results.add(
          TextContent(
            text: jsonEncode({
              'packageName': packageName,
              'latestVersion': latestVersion,
              'description': description,
              'scores': scores,
              'topics': topics,
              'licenses': licenses,
              'api': identifiers,
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
    } finally {
      client.close();
    }
  }

  static final pubDevTool = Tool(
    name: 'pub_dev_search',
    description:
        'Searches pub.dev for packages relevant to a given search query. '
        'The response will describe each result with its download count,'
        ' package description, topics, license, and a list of identifiers '
        'in the public api',

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
  ''',
        ),
      },
      required: ['query'],
    ),
  );
}

/// Utility for indexing json data structures.
///
/// Each element of [path] should be a `String`, `int` or `(String, String)`.
///
/// For each element `key` of [path], recurse into [json].
///
/// If the `key` is a String, the next json structure should be a Map, and have
/// `key` as a property. Recurse into that property.
///
/// If `key` is an `int`, the next json structure must be a List, with that
/// index. Recurse into that index.
///
/// If `key` in a `(String k, String v)` the next json structure must be a List
/// of maps, one of them having the property `k` with value `v`, recurse into
/// that map.
///
/// If at some point the types don't match throw a [FormatException].
///
/// Returns the result as a [T].
T dig<T>(dynamic json, List<dynamic> path) {
  var i = 0;
  String currentPath() => path.take(i).map((i) => '[$i]').join('');
  for (; i < path.length; i++) {
    outer:
    switch (path[i]) {
      case final String key:
        if (json is! Map) {
          throw FormatException('Expected a map at ${currentPath()}');
        }
        json = json[key];
      case final int key:
        if (json is! List) {
          throw FormatException('Expected a map at ${currentPath()}');
        }
        json = json[key];
      case (final String key, final String value):
        if (json is! List) {
          throw FormatException('Expected a map at ${currentPath()}');
        }
        final t = json;
        for (var j = 0; j < t.length; j++) {
          final element = t[j];
          if (element is! Map) {
            throw FormatException('Expected a map at ${currentPath()}[$j]');
          }
          if (element[key] == value) {
            json = element;
            break outer;
          }
        }
      case final key:
        throw ArgumentError('Bad key $key in', 'path');
    }
  }

  if (json is! T) throw FormatException('Unexpected value at $currentPath()');
  return json;
}
