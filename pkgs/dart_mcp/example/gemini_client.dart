// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:async/async.dart';
import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/server.dart';
import 'package:google_generative_ai/google_generative_ai.dart' as gemini;
import 'package:stream_channel/stream_channel.dart';

void main(List<String> args) {
  final geminiApiKey = Platform.environment['GEMINI_API_KEY'];
  if (geminiApiKey == null) {
    throw ArgumentError(
      'No environment variable GEMINI_API_KEY found, you must set one to your '
      'API key in order to run this client. You can get a key at '
      'https://aistudio.google.com/apikey.',
    );
  }

  final parsedArgs = argParser.parse(args);
  final serverCommands = parsedArgs['server'] as List<String>;
  GeminiClient(serverCommands, geminiApiKey: geminiApiKey);
}

final argParser =
    ArgParser()..addMultiOption(
      'server',
      abbr: 's',
      help: 'A command to run to start an MCP server',
    );

final class GeminiClient extends MCPClient with RootsSupport {
  final StreamQueue<String> stdinQueue;
  final List<String> serverCommands;
  final List<ServerConnection> serverConnections = [];
  final List<gemini.Tool> serverTools = [];
  final Map<String, ServerConnection> connectionForFunction = {};
  final gemini.GenerativeModel model;
  final List<gemini.Content> chatHistory = [];

  GeminiClient(this.serverCommands, {required String geminiApiKey})
    : stdinQueue = StreamQueue(
        stdin.transform(utf8.decoder).transform(const LineSplitter()),
      ),
      model = gemini.GenerativeModel(
        model: 'gemini-2.5-pro-exp-03-25',
        apiKey: geminiApiKey,
      ),
      super(
        ClientImplementation(name: 'Example gemini client', version: '0.1.0'),
      ) {
    addRoot(
      Root(uri: Directory.current.absolute.path, name: 'The working dir'),
    );
    _startChat();
  }

  void _startChat() async {
    print('Welcome to our example gemini chat bot!');
    await _connectOwnServer();
    if (serverCommands.isNotEmpty) {
      print('connecting to your MCP servers...');
      await _connectToServers();
    } else {
      print(
        'It looks like you didn\'t provide me with any servers, continuing '
        'as just a normal chat bot.',
      );
    }
    await _initializeServers();
    print('discovering capabilities...');
    await _listServerCapabilities();
    print(
      'I have ${serverTools.single.functionDeclarations!.length} tools '
      'available from the connected servers, feel free to ask me about them.',
    );
    print('ready to chat!');

    while (true) {
      chatHistory.add(gemini.Content.text(await stdinQueue.next));
      final modelResponse =
          (await model.generateContent(
            chatHistory,
            tools: serverTools,
          )).candidates.single.content;

      for (var part in modelResponse.parts) {
        switch (part) {
          case gemini.TextPart():
            _chatToUser(part.text);
          case gemini.FunctionCall():
            await _handleFunctionCall(part);
          default:
            throw UnimplementedError('Unhandled response type $modelResponse');
        }
      }
    }
  }

  // Prints `text` and adds it to the chat history
  void _chatToUser(String text) {
    print(text);
    chatHistory.add(gemini.Content.model([gemini.TextPart(text)]));
  }

  /// Handles a function call response from the model.
  Future<void> _handleFunctionCall(gemini.FunctionCall functionCall) async {
    _chatToUser(
      'It looks like you want to invoke tool ${functionCall.name} with args '
      '${jsonEncode(functionCall.args)}, is that correct? (y/n)',
    );
    final answer = await stdinQueue.peek;
    chatHistory.add(gemini.Content.text(answer));
    if (answer == 'y') {
      // We only peeked the answer, now lets consume it.
      await stdinQueue.skip(1);
      print('Running tool ...');
      chatHistory.add(gemini.Content.model([functionCall]));
      final connection = connectionForFunction[functionCall.name]!;
      final result = await connection.callTool(
        CallToolRequest(name: functionCall.name, arguments: functionCall.args),
      );
      final response = StringBuffer();
      for (var content in result.content) {
        switch (content) {
          case final TextContent content when content.isText:
            response.writeln(content.text);
          case final ImageContent content when content.isImage:
            chatHistory.add(
              gemini.Content.data('image/png', base64Decode(content.data)),
            );
            response.writeln('Image added to context');
          default:
            response.writeln('Got unsupported response type ${content.type}');
        }
      }
      _chatToUser(response.toString());
    }
  }

  /// Connects us to a local [GeminiChatBotServer].
  Future<void> _connectOwnServer() async {
    /// The client side of the communication channel - the stream is the
    /// incoming data and the sink is outgoing data.
    final clientController = StreamController<String>();

    /// The server side of the communication channel - the stream is the
    /// incoming data and the sink is outgoing data.
    final serverController = StreamController<String>();

    late final clientChannel = StreamChannel<String>.withCloseGuarantee(
      serverController.stream,
      clientController.sink,
    );
    late final serverChannel = StreamChannel<String>.withCloseGuarantee(
      clientController.stream,
      serverController.sink,
    );
    GeminiChatBotServer(channel: serverChannel);
    serverConnections.add(connectServer(clientChannel));
  }

  /// Connects to all servers using [serverCommands].
  Future<void> _connectToServers() async {
    for (var server in serverCommands) {
      serverConnections.add(await connectStdioServer(server, []));
    }
  }

  /// Initialization handshake.
  Future<void> _initializeServers() async {
    for (var connection in serverConnections) {
      final result = await connection.initialize(
        InitializeRequest(
          protocolVersion: protocolVersion,
          capabilities: capabilities,
          clientInfo: implementation,
        ),
      );
      if (result.protocolVersion != protocolVersion) {
        print(
          'Protocol version mismatch, expected $protocolVersion, '
          'got ${result.protocolVersion}, disconnecting from server',
        );
        await connection.shutdown();
        serverConnections.remove(connection);
      } else {
        connection.notifyInitialized(InitializedNotification());
      }
    }
  }

  /// Lists all the tools available the [serverConnections].
  Future<void> _listServerCapabilities() async {
    final functions = <gemini.FunctionDeclaration>[];
    for (var connection in serverConnections) {
      for (var tool in (await connection.listTools()).tools) {
        functions.add(
          gemini.FunctionDeclaration(
            tool.name,
            tool.description ?? '',
            _schemaToGeminiSchema(tool.inputSchema),
          ),
        );
        connectionForFunction[tool.name] = connection;
      }
    }
    serverTools.add(gemini.Tool(functionDeclarations: functions));
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
                nullable: objectSchema.required?.contains(entry.key),
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
        return gemini.Schema.array(
          description: description,
          items: _schemaToGeminiSchema(listSchema.items!),
          nullable: nullable,
        );
      case JsonType.num:
        return gemini.Schema.number(
          description: description,
          nullable: nullable,
        );
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
        throw UnimplementedError(
          'Unimplemented schema type ${inputSchema.type}',
        );
    }
  }
}

final class GeminiChatBotServer extends MCPServer with ToolsSupport {
  GeminiChatBotServer({required super.channel})
    : super.fromStreamChannel(
        implementation: ServerImplementation(
          name: 'Gemini Chat Bot',
          version: '0.1.0',
        ),
        instructions:
            'This server handles the specific tool interactions built '
            'into the gemini chat bot.',
      ) {
    registerTool(exitTool, (_) async {
      print('goodbye!');
      exit(0);
    });
  }

  static final exitTool = Tool(name: 'exit', inputSchema: Schema.object());
}
