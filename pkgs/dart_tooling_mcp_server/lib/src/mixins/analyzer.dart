// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:language_server_protocol/protocol_generated.dart' as lsp;
import 'package:meta/meta.dart';

import '../lsp/wire_format.dart';

/// Mix this in to any MCPServer to add support for analyzing Dart projects.
///
/// The MCPServer must already have the [ToolsSupport] and [LoggingSupport]
/// mixins applied.
base mixin DartAnalyzerSupport
    on ToolsSupport, LoggingSupport, RootsTrackingSupport {
  /// The LSP server connection for the analysis server.
  late final Peer _lspConnection;

  /// The actual process for the LSP server.
  late final Process _lspServer;

  /// The current diagnostics for a given file.
  Map<Uri, List<lsp.Diagnostic>> diagnostics = {};

  /// If currently analyzing, a completer which will be completed once analysis
  /// is over.
  Completer<void>? _doneAnalyzing = Completer();

  /// The current LSP workspace folder state.
  HashSet<lsp.WorkspaceFolder> _currentWorkspaceFolders =
      HashSet<lsp.WorkspaceFolder>(
        equals: (a, b) => a.uri == b.uri,
        hashCode: (a) => a.uri.hashCode,
      );

  @override
  FutureOr<InitializeResult> initialize(InitializeRequest request) async {
    // This should come first, assigns `clientCapabilities`.
    final result = await super.initialize(request);

    // We check for requirements and store a message to log after initialization
    // if some requirement isn't satisfied.
    final unsupportedReasons = <String>[
      if (!supportsRoots)
        'Project analysis requires the "roots" capability which is not '
            'supported. Analysis tools have been disabled.',
      if (Platform.environment['DART_SDK'] == null)
        'Project analysis requires a "DART_SDK" environment variable to be set '
            '(this should be the path to the root of the dart SDK). Analysis '
            'tools have been disabled.',
    ];

    if (unsupportedReasons.isEmpty) {
      if (await _initializeAnalyzerLspServer() case final failedReason?) {
        unsupportedReasons.add(failedReason);
      }
    }

    if (unsupportedReasons.isEmpty) {
      registerTool(analyzeFilesTool, _analyzeFiles);
    }

    // Don't call any methods on the client until we are fully initialized
    // (even logging).
    unawaited(
      initialized.then((_) {
        if (unsupportedReasons.isNotEmpty) {
          log(LoggingLevel.warning, unsupportedReasons.join('\n'));
        }
      }),
    );

    return result;
  }

  /// Initializes the analyzer lsp server.
  ///
  /// On success, returns `null`.
  ///
  /// On failure, returns a reason for the failure.
  Future<String?> _initializeAnalyzerLspServer() async {
    _lspServer = await Process.start('dart', [
      'language-server',
      // Required even though it is documented as the default.
      // https://github.com/dart-lang/sdk/issues/60574
      '--protocol',
      'lsp',
      // Uncomment these to log the analyzer traffic.
      // '--protocol-traffic-log',
      // 'language-server-protocol.log',
    ]);
    _lspServer.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) async {
          await initialized;
          log(LoggingLevel.warning, line, logger: 'DartLanguageServer');
        });

    _lspConnection =
        Peer(lspChannel(_lspServer.stdout, _lspServer.stdin))
          ..registerMethod(
            lsp.Method.textDocument_publishDiagnostics.toString(),
            _handleDiagnostics,
          )
          ..registerMethod(r'$/analyzerStatus', _handleAnalyzerStatus)
          ..registerFallback((Parameters params) {
            log(
              LoggingLevel.debug,
              () => 'Unhandled LSP message: ${params.method} - ${params.asMap}',
            );
          });

    unawaited(_lspConnection.listen());

    log(LoggingLevel.debug, 'Connecting to analyzer lsp server');
    lsp.InitializeResult? initializeResult;
    String? error;
    try {
      // Initialize with the server.
      initializeResult = lsp.InitializeResult.fromJson(
        (await _lspConnection.sendRequest(
              lsp.Method.initialize.toString(),
              lsp.InitializeParams(
                capabilities: lsp.ClientCapabilities(
                  workspace: lsp.WorkspaceClientCapabilities(
                    diagnostics: lsp.DiagnosticWorkspaceClientCapabilities(
                      refreshSupport: true,
                    ),
                  ),
                  textDocument: lsp.TextDocumentClientCapabilities(
                    publishDiagnostics:
                        lsp.PublishDiagnosticsClientCapabilities(),
                  ),
                ),
              ).toJson(),
            ))
            as Map<String, Object?>,
      );
      log(
        LoggingLevel.debug,
        'Completed initialize handshake analyzer lsp server',
      );
    } catch (e) {
      error = 'Error connecting to analyzer lsp server: $e';
    }

    if (initializeResult != null) {
      final workspaceSupport =
          initializeResult.capabilities.workspace?.workspaceFolders;
      if (workspaceSupport?.supported != true) {
        error ??= 'Workspaces are not supported by the LSP server';
      }
      if (workspaceSupport?.changeNotifications?.valueEquals(true) != true) {
        error ??=
            'Workspace change notifications are not supported by the LSP '
            'server';
      }
    }

    if (error != null) {
      _lspServer.kill();
      await _lspConnection.close();
    } else {
      _lspConnection.sendNotification(
        lsp.Method.initialized.toString(),
        lsp.InitializedParams().toJson(),
      );
    }
    return error;
  }

  @override
  Future<void> shutdown() async {
    await super.shutdown();
    _lspServer.kill();
    await _lspConnection.close();
  }

  /// Implementation of the [analyzeFilesTool], analyzes all the files in all
  /// workspace dirs.
  ///
  /// Waits for any pending analysis before returning.
  Future<CallToolResult> _analyzeFiles(CallToolRequest request) async {
    await _doneAnalyzing?.future;
    final messages = <Content>[];
    for (var entry in diagnostics.entries) {
      for (var diagnostic in entry.value) {
        final diagnosticJson = diagnostic.toJson();
        diagnosticJson['uri'] = entry.key.toString();
        messages.add(TextContent(text: jsonEncode(diagnosticJson)));
      }
    }
    if (messages.isEmpty) {
      messages.add(TextContent(text: 'No errors'));
    }
    return CallToolResult(content: messages);
  }

  /// Handles `$/analyzerStatus` events, which tell us when analysis starts and
  /// stops.
  void _handleAnalyzerStatus(Parameters params) {
    final isAnalyzing = params.asMap['isAnalyzing'] as bool;
    if (isAnalyzing) {
      // Leave existing completer in place - we start with one so we don't
      // respond too early to the first analyze request.
      _doneAnalyzing ??= Completer<void>();
    } else {
      assert(_doneAnalyzing != null);
      _doneAnalyzing?.complete();
      _doneAnalyzing = null;
    }
  }

  /// Handles `textDocument/publishDiagnostics` events.
  void _handleDiagnostics(Parameters params) {
    final diagnosticParams = lsp.PublishDiagnosticsParams.fromJson(
      params.value as Map<String, Object?>,
    );
    diagnostics[diagnosticParams.uri] = diagnosticParams.diagnostics;
    log(LoggingLevel.debug, {
      'uri': diagnosticParams.uri,
      'diagnostics':
          diagnosticParams.diagnostics.map((d) => d.toJson()).toList(),
    });
  }

  /// Update the LSP workspace dirs when our workspace [Root]s change.
  @override
  Future<void> updateRoots() async {
    await super.updateRoots();
    unawaited(() async {
      final newRoots = await roots;

      final oldWorkspaceFolders = _currentWorkspaceFolders;
      final newWorkspaceFolders =
          _currentWorkspaceFolders = HashSet<lsp.WorkspaceFolder>(
            equals: (a, b) => a.uri == b.uri,
            hashCode: (a) => a.uri.hashCode,
          )..addAll(newRoots.map((r) => r.asWorkspaceFolder));

      final added =
          newWorkspaceFolders.difference(oldWorkspaceFolders).toList();
      final removed =
          oldWorkspaceFolders.difference(newWorkspaceFolders).toList();

      // This can happen in the case of multiple notifications in quick
      // succession, the `roots` future will complete only after the state has
      // stabilized which can result in empty diffs.
      if (added.isEmpty && removed.isEmpty) {
        return;
      }

      final event = lsp.WorkspaceFoldersChangeEvent(
        added: added,
        removed: removed,
      );

      log(
        LoggingLevel.debug,
        () => 'Notifying of workspace root change: ${event.toJson()}',
      );

      _lspConnection.sendNotification(
        lsp.Method.workspace_didChangeWorkspaceFolders.toString(),
        lsp.DidChangeWorkspaceFoldersParams(event: event).toJson(),
      );
    }());
  }

  @visibleForTesting
  static final analyzeFilesTool = Tool(
    name: 'analyze_files',
    description: 'Analyzes the entire project for errors.',
    inputSchema: ObjectSchema(),
  );
}

extension on Root {
  /// Converts a [Root] to an [lsp.WorkspaceFolder].
  lsp.WorkspaceFolder get asWorkspaceFolder =>
      lsp.WorkspaceFolder(name: name ?? '', uri: Uri.parse(uri));
}
