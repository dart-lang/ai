// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// ignore_for_file: avoid_print

import 'package:dart_mcp/client.dart';
import 'package:google_generative_ai/google_generative_ai.dart' as gemini;

final class MyMCPClient extends MCPClient with RootsSupport {
  final Map<String, ServerConnection> connectionForFunction = {};
  final List<gemini.Tool> tools = [gemini.Tool(functionDeclarations: [])];
  final String projectUri;

  MyMCPClient({required this.projectUri})
    : super(ClientImplementation(name: 'Flutter Chat App', version: '1.0.0')) {
    addRoot(Root(uri: projectUri, name: 'Selected Project Directory'));
  }

  // Define capabilities for this client
  static final clientCapabilities = ClientCapabilities(
    roots: RootsCapabilities(),
  );

  Future<void> initializeServer(ServerConnection connection) async {
    final initResult = await connection.initialize(
      InitializeRequest(
        protocolVersion: ProtocolVersion.latestSupported,
        capabilities: clientCapabilities,
        clientInfo: implementation,
      ),
    );

    final serverName = connection.serverInfo?.name ?? 'unknown';
    if (initResult.protocolVersion != ProtocolVersion.latestSupported) {
      print(
        'Protocol version mismatch for $serverName, expected '
        '${ProtocolVersion.latestSupported}, got '
        '${initResult.protocolVersion}. Disconnecting.',
      );
      await connection.shutdown();
    } else {
      connection.notifyInitialized(InitializedNotification());
      print('MCP Server $serverName initialized.');

      if (connection.serverCapabilities.logging != null) {
        final logLevel = LoggingLevel.info;
        print('Setting log level to ${logLevel.name} for $serverName');
        connection.setLogLevel(SetLevelRequest(level: logLevel));
        connection.onLog.listen((event) {
          print(
            '[$serverName-log/${event.level.name}] ${event.logger != null ? '[${event.logger}] ' : ''}${event.data}',
          );
        });
      }

      try {
        final response = await connection.listTools();
        for (var tool in response.tools) {
          tools.single.functionDeclarations!.add(
            gemini.FunctionDeclaration(
              tool.name,
              tool.description ?? '',
              _schemaToGeminiSchema(tool.inputSchema),
            ),
          );
          connectionForFunction[tool.name] = connection;
          print(
            'Registered tool: ${tool.name} from ${connection.serverInfo?.name}',
          );
        }
      } catch (e) {
        print(
          'Error listing tools for ${connection.serverInfo?.name ?? 'a server'}: $e',
        );
      }
      return;
    }
  }
}

gemini.Schema _schemaToGeminiSchema(Schema inputSchema, {bool? nullable}) {
  final description = inputSchema.description;

  switch (inputSchema.type) {
    case JsonType.object:
      final objectSchema = inputSchema as ObjectSchema;
      Map<String, gemini.Schema>? properties;
      if (objectSchema.properties case final originalProperties?) {
        properties = {
          for (var entry in originalProperties.entries)
            entry.key: _schemaToGeminiSchema(
              entry.value,
              nullable: objectSchema.required?.contains(entry.key) ?? false,
            ),
        };
      }
      return gemini.Schema.object(
        description: description,
        properties: properties ?? {},
        nullable: nullable,
      );
    case JsonType.string:
      return gemini.Schema.string(
        description: inputSchema.description,
        nullable: nullable,
      );
    case JsonType.list:
      final listSchema = inputSchema as ListSchema;
      final itemSchema =
          listSchema.items == null
              ? gemini.Schema.string() // Fallback for missing item schema
              : _schemaToGeminiSchema(listSchema.items!);
      return gemini.Schema.array(
        description: description,
        items: itemSchema,
        nullable: nullable,
      );
    case JsonType.num:
      return gemini.Schema.number(description: description, nullable: nullable);
    case JsonType.int:
      return gemini.Schema.integer(
        description: description,
        nullable: nullable,
      );
    case JsonType.bool:
      return gemini.Schema.boolean(
        description: description,
        nullable: nullable,
      );
    default:
      throw UnimplementedError('Unimplemented schema type ${inputSchema.type}');
  }
}
