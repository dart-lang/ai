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
base mixin DartAnalyzerSupport on ToolsSupport, LoggingSupport {
  /// The LSP server connection for the analysis server.
  late final Peer _lspConnection;

  /// The actual process for the LSP server.
  late final Process _lspServer;

  /// The current diagnostics for a given file.
  Map<Uri, List<lsp.Diagnostic>> diagnostics = {};

  /// If currently analyzing, a completer which will be completed once analysis
  /// is over.
  Completer<void>? _doneAnalyzing = Completer();

  /// All known workspace roots.
  ///
  /// Identity is controlled by the [Root.uri].
  Set<Root> workspaceRoots = HashSet(
    equals: (r1, r2) => r2.uri == r2.uri,
    hashCode: (r) => r.uri.hashCode,
  );

  @override
  FutureOr<InitializeResult> initialize(InitializeRequest request) async {
    // We check for requirements and store a message to log after initialization
    // if some requirement isn't satisfied.
    var unsupportedReason =
        request.capabilities.roots == null
            ? 'Project analysis requires the "roots" capability which is not '
                'supported. Analysis tools have been disabled.'
            : (Platform.environment['DART_SDK'] == null
                ? 'Project analysis requires a "DART_SDK" environment variable '
                    'to be set (this should be the path to the root of the '
                    'dart SDK). Analysis tools have been disabled.'
                : null);

    unsupportedReason ??= await _initializeAnalyzerLspServer();
    if (unsupportedReason == null) {
      registerTool(analyzeFilesTool, _analyzeFiles);
      registerTool(resolveWorkspaceSymbolTool, _resolveWorkspaceSymbol);
    }

    // Don't call any methods on the client until we are fully initialized
    // (even logging).
    unawaited(
      initialized.then((_) {
        if (unsupportedReason != null) {
          log(LoggingLevel.warning, unsupportedReason);
        } else {
          // All requirements satisfied, ask the client for its roots.
          _listenForRoots();
        }
      }),
    );

    return super.initialize(request);
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
                    symbol: lsp.WorkspaceSymbolClientCapabilities(
                      symbolKind:
                          lsp.WorkspaceSymbolClientCapabilitiesSymbolKind(
                            valueSet: [
                              lsp.SymbolKind.Array,
                              lsp.SymbolKind.Boolean,
                              lsp.SymbolKind.Class,
                              lsp.SymbolKind.Constant,
                              lsp.SymbolKind.Constructor,
                              lsp.SymbolKind.Enum,
                              lsp.SymbolKind.EnumMember,
                              lsp.SymbolKind.Event,
                              lsp.SymbolKind.Field,
                              lsp.SymbolKind.File,
                              lsp.SymbolKind.Function,
                              lsp.SymbolKind.Interface,
                              lsp.SymbolKind.Key,
                              lsp.SymbolKind.Method,
                              lsp.SymbolKind.Module,
                              lsp.SymbolKind.Namespace,
                              lsp.SymbolKind.Null,
                              lsp.SymbolKind.Number,
                              lsp.SymbolKind.Obj,
                              lsp.SymbolKind.Operator,
                              lsp.SymbolKind.Package,
                              lsp.SymbolKind.Property,
                              lsp.SymbolKind.Str,
                              lsp.SymbolKind.Struct,
                              lsp.SymbolKind.TypeParameter,
                              lsp.SymbolKind.Variable,
                            ],
                          ),
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
      // Checks that we can set workspaces on the LSP server.
      final workspaceSupport =
          initializeResult.capabilities.workspace?.workspaceFolders;
      if (workspaceSupport?.supported != true) {
        error ??= 'Workspaces are not supported by the LSP server';
      } else if (workspaceSupport?.changeNotifications?.valueEquals(true) !=
          true) {
        error ??=
            'Workspace change notifications are not supported by the LSP '
            'server';
      }

      // Checks that we resolve workspace symbols.
      final workspaceSymbolProvider =
          initializeResult.capabilities.workspaceSymbolProvider;
      final symbolProvidersSupported =
          workspaceSymbolProvider != null &&
          workspaceSymbolProvider.map(
            (b) => b,
            (options) => options.resolveProvider == true,
          );
      if (!symbolProvidersSupported) {
        error ??=
            'Workspace symbol resolution is not supported by the LSP server';
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

  /// Implementation of the [resolveWorkspaceSymbolTool], resolves a given
  /// symbol or symbols in a workspace.
  Future<CallToolResult> _resolveWorkspaceSymbol(
    CallToolRequest request,
  ) async {
    await _doneAnalyzing?.future;
    final query = request.arguments!['query'] as String;
    final result = await _lspConnection.sendRequest(
      lsp.Method.workspace_symbol.toString(),
      lsp.WorkspaceSymbolParams(query: query).toJson(),
    );
    return CallToolResult(content: [TextContent(text: jsonEncode(result))]);
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

  /// Lists the roots, and listens for changes to them.
  ///
  /// Sends workspace change notifications to the LSP server based on the roots.
  void _listenForRoots() async {
    rootsListChanged!.listen((event) async {
      await _updateRoots();
    });
    await _updateRoots();
  }

  /// Updates the set of [workspaceRoots] and notifies the server.
  Future<void> _updateRoots() async {
    final newRoots = HashSet<Root>(
      equals: (r1, r2) => r1.uri == r2.uri,
      hashCode: (r) => r.uri.hashCode,
    )..addAll((await listRoots(ListRootsRequest())).roots);

    final removed = workspaceRoots.difference(newRoots);
    final added = newRoots.difference(workspaceRoots);
    workspaceRoots = newRoots;

    final event = lsp.WorkspaceFoldersChangeEvent(
      added: [for (var root in added) root.asWorkspaceFolder],
      removed: [for (var root in removed) root.asWorkspaceFolder],
    );

    log(
      LoggingLevel.debug,
      () => 'Notifying of workspace root change: ${event.toJson()}',
    );

    _lspConnection.sendNotification(
      lsp.Method.workspace_didChangeWorkspaceFolders.toString(),
      lsp.DidChangeWorkspaceFoldersParams(event: event).toJson(),
    );
  }

  @visibleForTesting
  static final analyzeFilesTool = Tool(
    name: 'analyze_files',
    description: 'Analyzes the entire project for errors.',
    inputSchema: Schema.object(),
    annotations: ToolAnnotations(title: 'Analyze projects', readOnlyHint: true),
  );

  @visibleForTesting
  static final resolveWorkspaceSymbolTool = Tool(
    name: 'resolve_workspace_symbol',
    description: 'Look up a symbol or symbols in all workspaces by name.',
    inputSchema: Schema.object(
      properties: {
        'query': Schema.string(
          description:
              'Queries are matched based on a case-insensitive partial name '
              'match, and do not support complex pattern matching, regexes, '
              'or scoped lookups.',
        ),
      },
      required: ['query'],
    ),
    annotations: ToolAnnotations(title: 'Project search', readOnlyHint: true),
  );
}

extension on Root {
  /// Converts a [Root] to an [lsp.WorkspaceFolder].
  lsp.WorkspaceFolder get asWorkspaceFolder =>
      lsp.WorkspaceFolder(name: name ?? '', uri: Uri.parse(uri));
}
