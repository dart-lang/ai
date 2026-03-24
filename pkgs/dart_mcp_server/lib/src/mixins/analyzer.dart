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

import '../features_configuration.dart';
import '../lsp/wire_format.dart';
import '../utils/analytics.dart';
import '../utils/cli_utils.dart';
import '../utils/file_system.dart';
import '../utils/names.dart';
import '../utils/package_uris.dart';
import '../utils/process_manager.dart';
import '../utils/sdk.dart';

/// Mix this in to any MCPServer to add support for analyzing Dart projects.
///
/// The MCPServer must already have the [ToolsSupport] and [LoggingSupport]
/// mixins applied.
base mixin DartAnalyzerSupport
    on ToolsSupport, LoggingSupport, RootsTrackingSupport, FileSystemSupport
    implements SdkSupport, ProcessManagerSupport {
  /// The LSP server connection for the analysis server.
  Peer? _lspConnection;

  /// The actual process for the LSP server.
  Process? _lspServer;

  /// The current diagnostics for a given file.
  Map<Uri, List<lsp.Diagnostic>> diagnostics = {};

  /// If currently analyzing, a completer which will be completed once analysis
  /// is over.
  Completer<void>? _doneAnalyzing = Completer();

  /// Completes the next time we get an analysis start event.
  Completer<void> _analysisStart = Completer();

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
      registerTool(lspTool, _lsp);
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

  @visibleForTesting
  static final List<Tool> allTools = [analyzeFilesTool, lspTool];

  /// Initializes the analyzer lsp server.
  ///
  /// On success, returns `null`.
  ///
  /// On failure, returns a reason for the failure.
  Future<String?> _initializeAnalyzerLspServer() async {
    final lspServer = await processManager.start([
      sdk.dartExecutablePath,
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
      ..registerMethod(
        lsp.Method.workspace_applyEdit.toString(),
        _handleApplyEdit,
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
                    applyEdit: true,
                    workspaceEdit: lsp.WorkspaceEditClientCapabilities(
                      changeAnnotationSupport:
                          // ignore: lines_longer_than_80_chars
                          lsp.WorkspaceEditClientCapabilitiesChangeAnnotationSupport(),
                    ),
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

    var rootConfigs = (request.arguments?[ParameterNames.roots] as List?)
        ?.cast<Map<String, Object?>>();
    final allRoots = await roots;

    if (rootConfigs != null && rootConfigs.isEmpty) {
      // If you provide an empty list of roots, we have nothing to do, but
      // don't want to default to all roots as you explicitly gave zero.
      return emptyRootsGivenResponse;
    }

    // Default to use the known roots if none were specified.
    rootConfigs ??= [
      for (final root in allRoots) {ParameterNames.root: root.uri},
    ];

    final requestedUris = <Uri>{};
    final requestedUriRoots = <Uri, Uri>{};
    for (final rootConfig in rootConfigs) {
      final validated = validateRootConfig(
        rootConfig,
        knownRoots: allRoots,
        fileSystem: fileSystem,
      );

      if (validated.errorResult case final error?) {
        return error;
      }

      final rootUri = Uri.parse(validated.root!.uri);

      if (validated.paths != null && validated.paths!.isNotEmpty) {
        for (final path in validated.paths!) {
          final uri = rootUri.resolve(path);
          requestedUris.add(uri);
          requestedUriRoots[uri] = rootUri;
        }
      } else {
        requestedUris.add(rootUri);
        requestedUriRoots[rootUri] = rootUri;
      }
    }
    final messages = <Content>[];

    final applyFixes =
        request.arguments?[ParameterNames.applyFixes] as bool? ?? false;
    if (applyFixes) {
      await _lspConnection!.sendRequest(
        lsp.Method.workspace_executeCommand.toString(),
        lsp.ExecuteCommandParams(
          command: 'dart.edit.fixAllInWorkspace',
          arguments: [],
        ).toJson(),
      );
      // The actual edits are asynchronous, we just assume some were applied
      // as a confirmation to the LLM that it was respected.
      messages.add(TextContent(text: 'Applied quick fixes'));

      if (_doneAnalyzing == null) {
        // Wait a bit for the new analysis to start if not currently analyzing.
        await _analysisStart.future.timeout(
          const Duration(seconds: 1),
          onTimeout: () {},
        );
      }
      await _doneAnalyzing?.future;
    }

    final filteredDiagnosticsByRoot = <Uri, Map<Uri, List<lsp.Diagnostic>>>{};
    for (final MapEntry(key: uri, value: diagnostics) in diagnostics.entries) {
      final entryPath = fileSystem.path.canonicalize(uri.toFilePath());
      if (requestedUriRoots[uri] case final rootUri?) {
        filteredDiagnosticsByRoot
            .putIfAbsent(rootUri, () => {})
            .putIfAbsent(uri, () => [])
            .addAll(diagnostics);
        continue;
      }

      for (final rootUri in requestedUriRoots.keys) {
        final requestedPath = fileSystem.path.canonicalize(
          rootUri.toFilePath(),
        );
        if (fileSystem.path.equals(requestedPath, entryPath) ||
            fileSystem.path.isWithin(requestedPath, entryPath)) {
          filteredDiagnosticsByRoot
              .putIfAbsent(rootUri, () => {})
              .putIfAbsent(uri, () => [])
              .addAll(diagnostics);
          break;
        }
      }
    }

    var sawDiagnostic = false;
    for (final MapEntry(key: rootUri, value: diagnostics)
        in filteredDiagnosticsByRoot.entries) {
      if (diagnostics.values.every((d) => d.isEmpty)) continue;

      messages.add(TextContent(text: '# Diagnostics for root $rootUri\n'));
      for (final MapEntry(key: sourceUri, value: diagnostics)
          in diagnostics.entries) {
        sawDiagnostic = true;
        messages.add(formatDiagnostics(rootUri, sourceUri, diagnostics));
      }
    }
    if (!sawDiagnostic) {
      messages.add(TextContent(text: 'No errors'));
    }

    return CallToolResult(content: messages);
  }

  Content formatDiagnostics(
    Uri rootUri,
    Uri sourceUri,
    List<lsp.Diagnostic> diagnostics,
  ) {
    final rootPath = fileSystem.path.fromUri(rootUri);
    final relativePath = fileSystem.path.relative(
      fileSystem.path.fromUri(sourceUri),
      from: rootPath,
    );
    final buffer = StringBuffer();
    for (final diagnostic in diagnostics) {
      buffer
        ..write(diagnostic.severity?.name ?? 'info')
        ..write(' • ')
        ..write(relativePath)
        ..write(':')
        ..write(diagnostic.range.start.line + 1)
        ..write(':')
        ..write(diagnostic.range.start.character + 1)
        ..write(' • ')
        ..write(diagnostic.message);
      if (diagnostic.code case final code?) {
        buffer
          ..write(' • ')
          ..write(code);
      }

      // Add any context messages as bullet list items.
      if (diagnostic.relatedInformation case final relatedInfo?) {
        for (var message in relatedInfo) {
          final contextPath = fileSystem.path.relative(
            fileSystem.path.fromUri(message.location.uri),
            from: rootPath,
          );

          buffer
            ..write(' • ')
            ..write(message.message)
            ..write(' at ')
            ..write(contextPath)
            ..write(':')
            ..write(message.location.range.start.line + 1)
            ..write(':')
            ..write(message.location.range.start.character + 1);
        }
      }
      buffer.writeln();
    }

    return Content.text(text: buffer.toString());
  }

  /// Implementation of the [lspTool].
  ///
  /// Dispatches the request to the appropriate handler based on the `command`
  /// argument.
  Future<CallToolResult> _lsp(CallToolRequest request) async {
    final errorResult = await _ensurePrerequisites(request);
    if (errorResult != null) return errorResult;

    final command = request.arguments![ParameterNames.command] as String;
    switch (command) {
      case LspCommands.hover:
        return _hover(request);
      case LspCommands.signatureHelp:
        return _signatureHelp(request);
      case LspCommands.resolveWorkspaceSymbol:
        return _resolveWorkspaceSymbol(request);
      default:
        return CallToolResult(
          isError: true,
          content: [TextContent(text: 'Unknown LSP command: $command')],
        );
    }
  }

  /// Implementation of the [LspCommands.resolveWorkspaceSymbol] command,
  /// resolves a given symbol or symbols in a workspace.
  Future<CallToolResult> _resolveWorkspaceSymbol(
    CallToolRequest request,
  ) async {
    final query = request.arguments![ParameterNames.query] as String;
    final result = await _lspConnection!.sendRequest(
      lsp.Method.workspace_symbol.toString(),
      lsp.WorkspaceSymbolParams(query: query).toJson(),
    );
    return CallToolResult(content: [TextContent(text: jsonEncode(result))]);
  }

  /// Implementation of the [LspCommands.signatureHelp] command, get signature
  /// help for a given position in a file.
  Future<CallToolResult> _signatureHelp(CallToolRequest request) async {
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

  /// Implementation of the [LspCommands.hover] command, get hover information
  /// for a given position in a file.
  Future<CallToolResult> _hover(CallToolRequest request) async {
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
      _analysisStart.complete(null);
      _analysisStart = Completer();
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

  /// Handles `workspace/applyEdit` requests from the LSP server.
  ///
  /// These happen when the agents requests to apply quick fixes or refactors.
  Future<Map<String, Object?>> _handleApplyEdit(Parameters params) async {
    final editParams = lsp.ApplyWorkspaceEditParams.fromJson(
      params.value as Map<String, Object?>,
    );
    await _applyWorkspaceEdit(editParams.edit);
    return lsp.ApplyWorkspaceEditResult(applied: true).toJson();
  }

  /// Applies a [lsp.WorkspaceEdit] to the actual filesystem.
  Future<void> _applyWorkspaceEdit(lsp.WorkspaceEdit edit) async {
    final changes = edit.changes;
    if (changes != null) {
      for (final MapEntry(key: uri, value: edits) in changes.entries) {
        await _applyTextEdits(uri, edits);
      }
    }
  }

  /// Actually applies a list of [edits] to a file at [uri] and writes the
  /// new contents.
  Future<void> _applyTextEdits(Uri uri, List<lsp.TextEdit> edits) async {
    if (edits.isEmpty) return;
    final file = fileSystem.file(cleanFilePath(uri.toFilePath()));
    if (!await file.exists()) return;
    final content = await file.readAsString();
    final newContent = _applyEditsToString(content, edits);
    await file.writeAsString(newContent);
  }

  /// Applies a list of [edits] to [content] and returns the new content.
  String _applyEditsToString(String content, List<lsp.TextEdit> edits) {
    if (edits.isEmpty) return content;

    // Precompute line offsets for efficient position lookups, ranges are given
    // as line/column pairs but we need actual character offsets.
    final lineOffsets = <int>[0];
    for (var i = 0; i < content.length; i++) {
      // Note that LSP ranges are based on utf16 code units and not grapheme
      // clusters, which simplifies this logic.
      if (content.codeUnitAt(i) == CodeUnits.newline) {
        lineOffsets.add(i + 1);
      }
    }

    // Convert a line/column pair to a character offset.
    int getOffset(lsp.Position pos) {
      if (pos.line >= lineOffsets.length) {
        throw StateError('Invalid line number: ${pos.line}');
      }
      final offset = lineOffsets[pos.line] + pos.character;
      if (offset > content.length) {
        throw StateError('Invalid character offset: $offset');
      }
      return offset;
    }

    // Sort edits by start position to apply them sequentially.
    final sortedEdits = List<lsp.TextEdit>.from(edits)
      ..sort((a, b) {
        final startA = getOffset(a.range.start);
        final startB = getOffset(b.range.start);
        return startA.compareTo(startB);
      });

    // Build up the string incrementally to avoid copying the whole string
    // multiple times. This is O(N) instead of O(N*M) where N is the number
    // of edits and M is the length of the content.
    final result = StringBuffer();
    var contentCursor = 0;
    int? lastEditEnd;
    for (final edit in sortedEdits) {
      final start = getOffset(edit.range.start);
      final end = getOffset(edit.range.end);
      if (lastEditEnd != null && start < lastEditEnd) {
        throw StateError('Overlapping edits are not supported');
      }

      result.write(content.substring(contentCursor, start));
      result.write(edit.newText);
      contentCursor = end;
      lastEditEnd = end;
    }
    if (contentCursor < content.length) {
      result.write(content.substring(contentCursor));
    }
    return result.toString();
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
    name: ToolNames.analyzeFiles.name,
    description: 'Analyzes specific paths, or the entire project, for errors.',
    inputSchema: Schema.object(
      properties: {
        ParameterNames.roots: rootsSchema(supportsPaths: true),
        ParameterNames.applyFixes: Schema.bool(
          description:
              'Whether or not to automatically apply quick fixes before '
              'returning diagnostics. Defaults to false.',
        ),
      },
      additionalProperties: false,
    ),
    annotations: ToolAnnotations(title: 'Analyze projects', readOnlyHint: true),
  )..categories = [FeatureCategory.analysis];

  @visibleForTesting
  static final lspTool = Tool(
    name: ToolNames.lsp.name,
    description:
        'Interacts with the Dart Language Server Protocol (LSP) to '
        'provide code intelligence features like hover, signature help, '
        'and symbol resolution.\n'
        'Commands:\n'
        '- hover: Get hover information (docs, types) at a position. '
        'Requires: uri, line, column.\n'
        '- signatureHelp: Get signature help at a position. '
        'Requires: uri, line, column.\n'
        '- resolveWorkspaceSymbol: Fuzzy search for symbols by name. '
        'Requires: query.',
    inputSchema: Schema.object(
      properties: {
        ParameterNames.command: EnumSchema.untitledSingleSelect(
          description: 'The LSP command to execute.',
          values: ['hover', 'signatureHelp', 'resolveWorkspaceSymbol'],
        ),
        ParameterNames.uri: Schema.string(
          description:
              'The URI of the file. Required for "hover" and '
              '"signatureHelp".',
        ),
        ParameterNames.line: Schema.int(
          description:
              'The zero-based line number. Required for "hover" '
              'and "signatureHelp".',
        ),
        ParameterNames.column: Schema.int(
          description:
              'The zero-based column number. Required for "hover" '
              'and "signatureHelp".',
        ),
        ParameterNames.query: Schema.string(
          description:
              'The search query. Required for "resolveWorkspaceSymbol".',
        ),
      },
      required: [ParameterNames.command],
      additionalProperties: false,
    ),
    annotations: ToolAnnotations(
      title: 'Language Server Protocol',
      readOnlyHint: true,
    ),
  )..categories = [FeatureCategory.analysis];

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

  @visibleForTesting
  static final emptyRootsGivenResponse = CallToolResult(
    isError: true,
    content: [
      TextContent(
        text:
            'A list of roots was provided, but it was empty. Either omit the '
            '`roots` parameter to use the default roots, or provide a '
            'non-empty list of roots.',
      ),
    ],
  )..failureReason = CallToolFailureReason.noRootsSet;
}

extension on Root {
  /// Converts a [Root] to an [lsp.WorkspaceFolder].
  lsp.WorkspaceFolder get asWorkspaceFolder =>
      lsp.WorkspaceFolder(name: name ?? '', uri: Uri.parse(uri));
}

extension LspCommands on Never {
  static const hover = 'hover';
  static const signatureHelp = 'signatureHelp';
  static const resolveWorkspaceSymbol = 'resolveWorkspaceSymbol';
}

extension CodeUnits on Never {
  static const newline = 10;
}

extension on lsp.DiagnosticSeverity {
  String get name {
    switch (this) {
      case lsp.DiagnosticSeverity.Error:
        return 'error';
      case lsp.DiagnosticSeverity.Warning:
        return 'warning';
      case lsp.DiagnosticSeverity.Information:
        return 'info';
      case lsp.DiagnosticSeverity.Hint:
        return 'hint';
      default:
        return 'info';
    }
  }
}
