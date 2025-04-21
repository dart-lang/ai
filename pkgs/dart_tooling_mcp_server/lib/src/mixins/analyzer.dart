// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:language_server_protocol/protocol_custom_generated.dart' as lsp;
import 'package:language_server_protocol/protocol_generated.dart' as lsp;
import 'package:language_server_protocol/protocol_special.dart' as lsp;

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

  /// All known workspace roots.
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
      '--protocol',
      'lsp',
      '--protocol-traffic-log',
      'language-server-protocol.log',
    ]);
    _lspServer.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          stderr.writeln('[StdErr from analyzer lsp server]: $line');
        });
    final channel = lspChannel(_lspServer.stdout, _lspServer.stdin);
    _lspConnection = Peer(channel);

    _lspConnection.registerMethod(
      lsp.Method.textDocument_publishDiagnostics.toString(),
      _handleDiagnostics,
    );

    stderr.writeln('initializing lsp server');
    lsp.InitializeResult? initializeResult;
    try {
      /// Initialize with the server.
      lsp.InitializeResult.fromJson(
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
    } catch (e, s) {
      stderr.writeln('error initializing lsp server');
      stderr.writeln(e);
      stderr.writeln(s);
      return 'error initializing lsp server';
    }
    stderr.writeln('done initializing lsp server');

    String? error;
    final workspaceSupport =
        initializeResult!.capabilities.workspace?.workspaceFolders;
    if (workspaceSupport?.supported != true) {
      error = 'Workspaces are not supported by the LSP server';
    }
    if (workspaceSupport?.changeNotifications?.valueEquals(true) != true) {
      error =
          'Workspace change notifications are not supported by the LSP '
          'server';
    }

    if (error != null) {
      _lspServer.kill();
      await _lspConnection.close();
    } else {
      _lspConnection.sendNotification(lsp.Method.initialized.toString());
    }

    return error;
  }

  @override
  Future<void> shutdown() async {
    await super.shutdown();
    _lspServer.kill();
    await _lspConnection.close();
  }

  void _handleDiagnostics(Parameters params) {
    final diagnosticParams = lsp.PublishDiagnosticsParams.fromJson(
      params.value as Map<String, Object?>,
    );
    diagnostics[diagnosticParams.uri] = diagnosticParams.diagnostics;
    log(LoggingLevel.error, {
      'uri': diagnosticParams.uri,
      'diagnostics':
          diagnosticParams.diagnostics.map((d) => d.toJson()).toList(),
    }, logger: 'Static errors from a root!');
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
    _lspConnection.sendNotification(
      lsp.Method.workspace_didChangeWorkspaceFolders.toString(),
      lsp.WorkspaceFoldersChangeEvent(
        added: [for (var root in added) root.asWorkspaceFolder],
        removed: [for (var root in removed) root.asWorkspaceFolder],
      ),
    );
  }
}

extension on Root {
  lsp.WorkspaceFolder get asWorkspaceFolder =>
      lsp.WorkspaceFolder(name: name ?? '', uri: Uri.parse(uri));
}
