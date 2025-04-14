// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:dart_mcp/server.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';

/// Mix this in to any MCPServer to add support for analyzing Dart projects.
///
/// The MCPServer must already have the [ToolsSupport] and [LoggingSupport]
/// mixins applied.
base mixin DartAnalyzerSupport on ToolsSupport, LoggingSupport {
  /// The analyzed contexts.
  AnalysisContextCollection? _analysisContexts;

  /// All active directory watcher streams.
  ///
  /// The watcher package doesn't let you close watchers, you just have to
  /// stop listening to their streams instead, so we store the stream
  /// subscriptions instead of the watchers themselves.
  final List<StreamSubscription> _watchSubscriptions = [];

  @override
  FutureOr<InitializeResult> initialize(InitializeRequest request) {
    if (request.capabilities.roots == null) {
      throw StateError(
        'This server requires the "roots" capability to be implemented.',
      );
    }
    registerTool(analyzeFilesTool, _analyzeFiles);
    initialized.then(_listenForRoots);
    return super.initialize(request);
  }

  @override
  Future<void> shutdown() async {
    await super.shutdown();
    await _analysisContexts?.dispose();
    _disposeWatchSubscriptions();
  }

  /// Cancels all [_watchSubscriptions] and clears the list.
  void _disposeWatchSubscriptions() async {
    for (var subscription in _watchSubscriptions) {
      unawaited(subscription.cancel());
    }
    _watchSubscriptions.clear();
  }

  /// Lists the roots, and listens for changes to them.
  ///
  /// Whenever new roots are found, creates a new [AnalysisContextCollection].
  void _listenForRoots([void _]) async {
    rootsListChanged!.listen((event) async {
      unawaited(_analysisContexts?.dispose());
      _analysisContexts = null;
      _createAnalysisContext(await listRoots(ListRootsRequest()));
    });
    _createAnalysisContext(await listRoots(ListRootsRequest()));
  }

  /// Creates an analysis context from a list of roots.
  //
  // TODO: Better configuration for the DART_SDK location.
  void _createAnalysisContext(ListRootsResult result) async {
    final sdkPath = Platform.environment['DART_SDK'];
    if (sdkPath == null) {
      throw StateError('DART_SDK environment variable not set');
    }

    final paths = <String>[];
    for (var root in result.roots) {
      final uri = Uri.parse(root.uri);
      if (uri.scheme != 'file') {
        throw ArgumentError.value(
          root.uri,
          'uri',
          'Only file scheme uris are allowed for roots',
        );
      }
      paths.add(p.normalize(uri.path));
    }

    _disposeWatchSubscriptions();

    for (var rootPath in paths) {
      final watcher = DirectoryWatcher(rootPath);
      _watchSubscriptions.add(
        watcher.events.listen((event) {
          _analysisContexts
              ?.contextFor(event.path)
              .changeFile(p.normalize(event.path));
        }),
      );
    }

    _analysisContexts = AnalysisContextCollection(
      includedPaths: paths,
      sdkPath: sdkPath,
    );
  }

  /// Implementation of the [analyzeFilesTool], analyzes the requested files
  /// under the requested project roots.
  Future<CallToolResult> _analyzeFiles(CallToolRequest request) async {
    final contexts = _analysisContexts;
    if (contexts == null) {
      return CallToolResult(
        content: [
          TextContent(
            text:
                'Analysis not yet ready, please wait a few seconds and try '
                'again.',
          ),
        ],
        isError: true,
      );
    }

    final messages = <TextContent>[];
    final rootConfigs =
        (request.arguments!['roots'] as List).cast<Map<String, Object?>>();
    for (var rootConfig in rootConfigs) {
      final rootUri = Uri.parse(rootConfig['root'] as String);
      if (rootUri.scheme != 'file') {
        return CallToolResult(
          content: [
            TextContent(
              text:
                  'Only file scheme uris are allowed for roots, but got '
                  '$rootUri',
            ),
          ],
          isError: true,
        );
      }
      final paths = (rootConfig['paths'] as List?)?.cast<String>();
      if (paths == null) {
        return CallToolResult(
          content: [
            TextContent(
              text:
                  'Missing required argument `paths`, which should be the list '
                  'of relative paths to analyze.',
            ),
          ],
          isError: true,
        );
      }

      final context = contexts.contextFor(p.normalize(rootUri.path));
      await context.applyPendingFileChanges();

      for (var path in paths) {
        final normalized = p.normalize(
          p.isAbsolute(path) ? path : p.join(rootUri.path, path),
        );
        final errorsResult = await context.currentSession.getErrors(normalized);
        if (errorsResult is! ErrorsResult) {
          return CallToolResult(
            content: [
              TextContent(
                text: 'Error computing analyzer errors $errorsResult',
              ),
            ],
          );
        }
        for (var error in errorsResult.errors) {
          messages.add(TextContent(text: 'Error: ${error.message}'));
          if (error.correctionMessage case final correctionMessage?) {
            messages.add(TextContent(text: correctionMessage));
          }
        }
      }
    }

    return CallToolResult(content: messages);
  }

  @visibleForTesting
  static final analyzeFilesTool = Tool(
    name: 'analyze_files',
    description:
        'Analyzes the requested file paths under the specified project roots '
        'and returns the results as a list of messages.',
    inputSchema: ObjectSchema(
      properties: {
        'roots': ListSchema(
          title: 'All projects roots to analyze',
          description:
              'These must match a root returned by a call to "listRoots".',
          items: ObjectSchema(
            properties: {
              'root': StringSchema(
                title: 'The URI of the project root to analyze.',
              ),
              'paths': ListSchema(
                title:
                    'Relative or absolute paths to analyze under the '
                    '"root", must correspond to files and not directories.',
                items: StringSchema(),
              ),
            },
            required: ['root'],
          ),
        ),
      },
      required: ['roots'],
    ),
  );
}
