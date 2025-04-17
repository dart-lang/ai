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
  DashClient(
    serverCommands,
    geminiApiKey: geminiApiKey,
    verbose: parsedArgs['verbose'] == true,
  );
}

final argParser =
    ArgParser()
      ..addMultiOption(
        'server',
        abbr: 's',
        help: 'A command to run to start an MCP server',
      )
      ..addOption(
        'verbose',
        abbr: 'v',
        help: 'Enables verbose logging for logs from servers.',
      );

final class DashClient extends MCPClient with RootsSupport {
  final StreamQueue<String> stdinQueue;
  final List<String> serverCommands;
  final List<ServerConnection> serverConnections = [];
  final Map<String, ServerConnection> connectionForFunction = {};
  final List<gemini.Content> chatHistory = [];
  final gemini.GenerativeModel model;
  final bool verbose;

  DashClient(
    this.serverCommands, {
    required String geminiApiKey,
    this.verbose = false,
  }) : model = gemini.GenerativeModel(
         // model: 'gemini-2.5-pro-exp-03-25',
         model: 'gemini-2.0-flash',
         apiKey: geminiApiKey,
         systemInstruction: systemInstructions,
       ),
       stdinQueue = StreamQueue(
         stdin.transform(utf8.decoder).transform(const LineSplitter()),
       ),
       super(
         ClientImplementation(name: 'Example gemini client', version: '0.1.0'),
       ) {
    addRoot(
      Root(
        uri: Directory.current.absolute.uri.toString(),
        name: 'The working dir',
      ),
    );
    _startChat();
  }

  void _startChat() async {
    await _connectOwnServer();
    if (serverCommands.isNotEmpty) {
      await _connectToServers();
    }
    await _initializeServers();
    _listenToLogs();
    final serverTools = await _listServerCapabilities();

    // If assigned then it is used as the next input from the user
    // instead of reading from stdin.
    String? continuation =
        'Please introduce yourself and explain how you can help';
    while (true) {
      final nextMessage = continuation ?? await stdinQueue.next;
      continuation = null;
      chatHistory.add(gemini.Content.text(nextMessage));
      final modelResponse =
          (await model.generateContent(
            chatHistory,
            tools: serverTools,
          )).candidates.single.content;

      for (var part in modelResponse.parts) {
        switch (part) {
          case gemini.TextPart():
            await _chatToUser(part.text);
          case gemini.FunctionCall():
            continuation = await _handleFunctionCall(part);
          default:
            print('Unrecognized response type from the model $modelResponse');
        }
      }
    }
  }

  /// Prints `text` and adds it to the chat history
  Future<void> _chatToUser(String text) async {
    final dashSpeakResponse =
        (await model.generateContent([
          gemini.Content.text(
            'Please rewrite the following message in your own voice',
          ),
          gemini.Content.text(text),
        ])).candidates.single.content;
    final dashText = StringBuffer();
    for (var part in dashSpeakResponse.parts.whereType<gemini.TextPart>()) {
      dashText.write(part.text);
    }
    print(dashText);
    chatHistory.add(
      gemini.Content.model([gemini.TextPart(dashText.toString())]),
    );
  }

  /// Handles a function call response from the model.
  Future<String?> _handleFunctionCall(gemini.FunctionCall functionCall) async {
    await _chatToUser(
      'It looks like you want to invoke tool ${functionCall.name} with args '
      '${jsonEncode(functionCall.args)}, is that correct?',
    );
    final userResponse = await stdinQueue.next;
    final wasApproval = await _analyzeSentiment(userResponse);

    // If they did not approve the action, just treat their response as a
    // prompt.
    if (!wasApproval) return userResponse;

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
            gemini.Content.data(content.mimeType, base64Decode(content.data)),
          );
          response.writeln('Image added to context');
        default:
          response.writeln('Got unsupported response type ${content.type}');
      }
    }
    await _chatToUser(response.toString());
    return null;
  }

  /// Analyzes a user [message] to see if it looks like they approved of the
  /// previous action.
  Future<bool> _analyzeSentiment(String message) async {
    if (message == 'y' || message == 'yes') return true;
    final sentimentResult =
        (await model.generateContent([
          gemini.Content.text(
            'Analyze the sentiment of the following response. If you are '
            'highly confident that the user approves of running the previous '
            'action then respond with a single character "y".',
          ),
          gemini.Content.text(message),
        ])).candidates.single.content;
    final response = StringBuffer();
    for (var part in sentimentResult.parts.whereType<gemini.TextPart>()) {
      response.write(part.text.trim());
    }
    return response.toString() == 'y';
  }

  /// Connects us to a local [DashChatBotServer].
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
    DashChatBotServer(this, channel: serverChannel);
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
          protocolVersion: ProtocolVersion.latestSupported,
          capabilities: capabilities,
          clientInfo: implementation,
        ),
      );
      if (result.protocolVersion != ProtocolVersion.latestSupported) {
        print(
          'Protocol version mismatch, expected '
          '${ProtocolVersion.latestSupported}, got ${result.protocolVersion}, '
          'disconnecting from server',
        );
        await connection.shutdown();
        serverConnections.remove(connection);
      } else {
        connection.notifyInitialized(InitializedNotification());
      }
    }
  }

  /// Listens for log messages on all [serverConnections] that support logging.
  void _listenToLogs() {
    for (var connection in serverConnections) {
      if (connection.serverCapabilities.logging == null) {
        continue;
      }

      connection.setLogLevel(
        SetLevelRequest(
          level: verbose ? LoggingLevel.debug : LoggingLevel.warning,
        ),
      );
      connection.onLog.listen((event) {
        print(
          'Server Log(${event.level.name}): '
          '${event.logger != null ? '[${event.logger}] ' : ''}${event.data}',
        );
      });
    }
  }

  /// Lists all the tools available the [serverConnections].
  Future<List<gemini.Tool>> _listServerCapabilities() async {
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
    return [gemini.Tool(functionDeclarations: functions)];
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

final class DashChatBotServer extends MCPServer with ToolsSupport {
  final DashClient client;

  DashChatBotServer(this.client, {required super.channel})
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

    registerTool(removeImagesTool, (_) async {
      final oldLength = client.chatHistory.length;
      // TODO: Something more robust than this, maybe just remove them by object
      // reference.
      client.chatHistory.removeWhere(
        (content) => content.parts.first is gemini.DataPart,
      );
      return CallToolResult(
        content: [
          TextContent(
            text:
                'Removed ${oldLength - client.chatHistory.length} images from '
                'the context.',
          ),
        ],
      );
    });
  }

  static final exitTool = Tool(name: 'exit', inputSchema: Schema.object());

  static final removeImagesTool = Tool(
    name: 'removeImagesFromContext',
    description: 'Removes all images from the chat context',
    inputSchema: Schema.object(),
  );
}

final systemInstructions = gemini.Content.system('''
You are a developer assistant for Dart and Flutter apps. Your persona is a cute
blue hummingbird named Dash, and you are also the mascot for the Dart and Flutter
brands. Your personality is extremely cheery and bright, and your tone is always
positive.

You can help developers by connecting into the live state of their apps, helping
them with all aspects of the software development lifecycle.

If a user asks about an error in the app, you should have several tools
available to you to aid in debugging, so make sure to use those.
''');
