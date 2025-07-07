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
import '../utils/analytics.dart';
import '../utils/constants.dart';
import '../utils/sdk.dart';

/// Mix this in to any MCPServer to add support for analyzing Dart projects.
///
/// The MCPServer must already have the [ToolsSupport] and [LoggingSupport]
/// mixins applied.
base mixin DartAnalyzerSupport
    on ToolsSupport, LoggingSupport, RootsTrackingSupport
    implements SdkSupport {
  /// The LSP server connection for the analysis server.
  Peer? _lspConnection;

  /// The actual process for the LSP server.
  Process? _lspServer;

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
      if (sdk.dartSdkPath == null)
        'Project analysis requires a Dart SDK but none was given. Analysis '
            'tools have been disabled.',
    ];

    if (unsupportedReasons.isEmpty) {
      if (await _initializeAnalyzerLspServer() case final failedReason?) {
        unsupportedReasons.add(failedReason);
      }
    }

    if (unsupportedReasons.isEmpty) {
      registerTool(analyzeFilesTool, _analyzeFiles);
      registerTool(resolveWorkspaceSymbolTool, _resolveWorkspaceSymbol);
      registerTool(signatureHelpTool, _signatureHelp);
      registerTool(hoverTool, _hover);
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
    final lspServer = await Process.start(sdk.dartExecutablePath, [
      'language-server',
      // Required even though it is documented as the default.
      // https://github.com/dart-lang/sdk/issues/60574
      '--protocol',
      'lsp',
      // Uncomment these to log the analyzer traffic.
      // '--protocol-traffic-log',
      // 'language-server-protocol.log',
    ]);
    _lspServer = lspServer;
    lspServer.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) async {
          await initialized;
          log(LoggingLevel.warning, line, logger: 'DartLanguageServer');
        });

    final lspConnection = Peer(lspChannel(lspServer.stdout, lspServer.stdin))
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
    _lspConnection = lspConnection;

    unawaited(lspConnection.listen());

    log(LoggingLevel.debug, 'Connecting to analyzer lsp server');
    lsp.InitializeResult? initializeResult;
    String? error;
    try {
      // Initialize with the server.
      initializeResult = lsp.InitializeResult.fromJson(
        (await lspConnection.sendRequest(
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
                    hover: lsp.HoverClientCapabilities(),
                    publishDiagnostics:
                        lsp.PublishDiagnosticsClientCapabilities(),
                    signatureHelp: lsp.SignatureHelpClientCapabilities(),
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
      lspServer.kill();
      await lspConnection.close();
    } else {
      lspConnection.sendNotification(
        lsp.Method.initialized.toString(),
        lsp.InitializedParams().toJson(),
      );
    }
    return error;
  }

  @override
  Future<void> shutdown() async {
    await super.shutdown();
    _lspServer?.kill();
    await _lspConnection?.close();
  }

  /// Implementation of the [analyzeFilesTool], analyzes all the files in all
  /// workspace dirs.
  ///
  /// Waits for any pending analysis before returning.
  Future<CallToolResult> _analyzeFiles(CallToolRequest request) async {
    final errorResult = await _ensurePrerequisites(request);
    if (errorResult != null) return errorResult;

    final messages = <Content>[];
    for (var entry in diagnostics.entries) {
      for (var diagnostic in entry.value) {
        final diagnosticJson = diagnostic.toJson();
        diagnosticJson[ParameterNames.uri] = entry.key.toString();
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
    final errorResult = await _ensurePrerequisites(request);
    if (errorResult != null) return errorResult;

    final query = request.arguments![ParameterNames.query] as String;
    final result = await _lspConnection!.sendRequest(
      lsp.Method.workspace_symbol.toString(),
      lsp.WorkspaceSymbolParams(query: query).toJson(),
    );
    return CallToolResult(content: [TextContent(text: jsonEncode(result))]);
  }

  /// Implementation of the [signatureHelpTool], get signature help for a given
  /// position in a file.
  Future<CallToolResult> _signatureHelp(CallToolRequest request) async {
    final errorResult = await _ensurePrerequisites(request);
    if (errorResult != null) return errorResult;

    final uri = Uri.parse(request.arguments![ParameterNames.uri] as String);
    final position = lsp.Position(
      line: request.arguments![ParameterNames.line] as int,
      character: request.arguments![ParameterNames.column] as int,
    );
    final result = await _lspConnection!.sendRequest(
      lsp.Method.textDocument_signatureHelp.toString(),
      lsp.SignatureHelpParams(
        textDocument: lsp.TextDocumentIdentifier(uri: uri),
        position: position,
      ).toJson(),
    );
    return CallToolResult(content: [TextContent(text: jsonEncode(result))]);
  }

  /// Implementation of the [hoverTool], get hover information for a given
  /// position in a file.
  Future<CallToolResult> _hover(CallToolRequest request) async {
    final errorResult = await _ensurePrerequisites(request);
    if (errorResult != null) return errorResult;

    final uri = Uri.parse(request.arguments![ParameterNames.uri] as String);
    final position = lsp.Position(
      line: request.arguments![ParameterNames.line] as int,
      character: request.arguments![ParameterNames.column] as int,
    );
    final result = await _lspConnection!.sendRequest(
      lsp.Method.textDocument_hover.toString(),
      lsp.HoverParams(
        textDocument: lsp.TextDocumentIdentifier(uri: uri),
        position: position,
      ).toJson(),
    );
    return CallToolResult(content: [TextContent(text: jsonEncode(result))]);
  }

  /// Ensures that all prerequisites for any analysis task are met.
  ///
  /// Returns an error response if any prerequisite is not met, otherwise
  /// returns `null`.
  Future<CallToolResult?> _ensurePrerequisites(CallToolRequest request) async {
    final roots = await this.roots;
    if (roots.isEmpty) {
      return noRootsSetResponse;
    }
    await _doneAnalyzing?.future;
    return null;
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
      ParameterNames.uri: diagnosticParams.uri,
      'diagnostics': diagnosticParams.diagnostics
          .map((d) => d.toJson())
          .toList(),
    });
  }

  /// Update the LSP workspace dirs when our workspace [Root]s change.
  @override
  Future<void> updateRoots() async {
    await super.updateRoots();
    unawaited(() async {
      final newRoots = await roots;

      final oldWorkspaceFolders = _currentWorkspaceFolders;
      final newWorkspaceFolders = _currentWorkspaceFolders =
          HashSet<lsp.WorkspaceFolder>(
            equals: (a, b) => a.uri == b.uri,
            hashCode: (a) => a.uri.hashCode,
          )..addAll(newRoots.map((r) => r.asWorkspaceFolder));

      final added = newWorkspaceFolders
          .difference(oldWorkspaceFolders)
          .toList();
      final removed = oldWorkspaceFolders
          .difference(newWorkspaceFolders)
          .toList();

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

      _lspConnection!.sendNotification(
        lsp.Method.workspace_didChangeWorkspaceFolders.toString(),
        lsp.DidChangeWorkspaceFoldersParams(event: event).toJson(),
      );
    }());
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
    description:
        'Look up a symbol or symbols in all workspaces by name. Can be used '
        'to validate that a symbol exists or discover small spelling '
        'mistakes, since the search is fuzzy.',
    inputSchema: Schema.object(
      properties: {
        ParameterNames.query: Schema.string(
          description:
              'Queries are matched based on a case-insensitive partial name '
              'match, and do not support complex pattern matching, regexes, '
              'or scoped lookups.',
        ),
      },
      description:
          'Returns all close matches to the query, with their names '
          'and locations. Be sure to check the name of the responses to ensure '
          'it looks like the thing you were searching for.',
      required: [ParameterNames.query],
    ),
    annotations: ToolAnnotations(title: 'Project search', readOnlyHint: true),
  );

  @visibleForTesting
  static final signatureHelpTool = Tool(
    name: 'signature_help',
    description:
        'Get signature help for an API being used at a given cursor '
        'position in a file.',
    inputSchema: _locationSchema,
    annotations: ToolAnnotations(title: 'Signature help', readOnlyHint: true),
  );

  @visibleForTesting
  static final hoverTool = Tool(
    name: 'hover',
    description:
        'Get hover information at a given cursor position in a file. This can '
        'include documentation, type information, etc for the text at that '
        'position.',
    inputSchema: _locationSchema,
    annotations: ToolAnnotations(
      title: 'Hover information',
      readOnlyHint: true,
    ),
  );

  @visibleForTesting
  static final noRootsSetResponse = CallToolResult(
    isError: true,
    content: [
      TextContent(
        text:
            'No roots set. At least one root must be set in order to use this '
            'tool.',
      ),
    ],
  )..failureReason = CallToolFailureReason.noRootsSet;
}

/// Common schema for tools that require a file URI, line, and column.
final _locationSchema = Schema.object(
  properties: {
    ParameterNames.uri: Schema.string(description: 'The URI of the file.'),
    ParameterNames.line: Schema.int(
      description: 'The zero-based line number of the cursor position.',
    ),
    ParameterNames.column: Schema.int(
      description: 'The zero-based column number of the cursor position.',
    ),
  },
  required: [ParameterNames.uri, ParameterNames.line, ParameterNames.column],
);

extension on Root {
  /// Converts a [Root] to an [lsp.WorkspaceFolder].
  lsp.WorkspaceFolder get asWorkspaceFolder =>
      lsp.WorkspaceFolder(name: name ?? '', uri: Uri.parse(uri));
}
