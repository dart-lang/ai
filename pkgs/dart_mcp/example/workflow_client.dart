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
  WorkflowClient(
    serverCommands,
    geminiApiKey: geminiApiKey,
    verbose: parsedArgs.flag('verbose'),
  );
}

final argParser =
    ArgParser()
      ..addMultiOption(
        'server',
        abbr: 's',
        help: 'A command to run to start an MCP server',
      )
      ..addFlag(
        'verbose',
        abbr: 'v',
        help: 'Enables verbose logging for logs from servers.',
      );

final class WorkflowClient extends MCPClient with RootsSupport {
  WorkflowClient(
    this.serverCommands, {
    required String geminiApiKey,
    this.verbose = false,
  }) : model = gemini.GenerativeModel(
         model: 'gemini-2.5-pro-preview-03-25',
         //  model: 'gemini-2.0-flash',
         apiKey: geminiApiKey,
         systemInstruction: systemInstructions,
       ),
       stdinQueue = StreamQueue(
         stdin.transform(utf8.decoder).transform(const LineSplitter()),
       ),
       super(
         ClientImplementation(name: 'Gemini workflow client', version: '0.1.0'),
       ) {
    addRoot(
      Root(
        uri: Directory.current.absolute.uri.toString(),
        name: 'The working dir',
      ),
    );
    _startChat();
  }

  final StreamQueue<String> stdinQueue;
  final List<String> serverCommands;
  final List<ServerConnection> serverConnections = [];
  final Map<String, ServerConnection> connectionForFunction = {};
  final List<gemini.Content> chatHistory = [];
  final gemini.GenerativeModel model;
  final bool verbose;

  void _startChat() async {
    await _connectOwnServer();
    if (serverCommands.isNotEmpty) {
      await _connectToServers();
    }
    await _initializeServers();
    _listenToLogs();
    final serverTools = await _listServerCapabilities();

    // Introduce yourself.
    _addToHistory('Please introduce yourself and explain how you can help.');
    final introResponse =
        (await model.generateContent(
          chatHistory,
          tools: serverTools,
        )).candidates.single.content;
    _handleModelResponse(introResponse);

    final userPrompt = await _waitForInputAndAddToHistory();
    await _makeAndExecutePlan(userPrompt, serverTools);
  }

  void _handleModelResponse(gemini.Content response) {
    for (var part in response.parts) {
      switch (part) {
        case gemini.TextPart():
          _chatToUser(part.text);
        default:
          print('Unrecognized response type from the model $response');
      }
    }
  }

  Future<void> _makeAndExecutePlan(
    String userPrompt,
    List<gemini.Tool> serverTools, {
    bool editPreviousPlan = false,
  }) async {
    final instruction =
        editPreviousPlan
            ? 'Edit the previous plan with the following corrections:'
            : 'Create a new plan for the following task:';
    final planPrompt =
        '$instruction\n$userPrompt. After you have made a plan, ask the user '
        'if they wish to proceed or if they want to make any changes to your '
        'plan.';
    _addToHistory(planPrompt);

    final planResponse =
        (await model.generateContent(
          chatHistory,
          tools: serverTools,
        )).candidates.single.content;
    _handleModelResponse(planResponse);

    final userResponse = await _waitForInputAndAddToHistory();
    final wasApproval = await _analyzeSentiment(userResponse);
    print('[DEBUG] plan approved: $wasApproval');
    if (!wasApproval) {
      await _makeAndExecutePlan(
        userResponse,
        serverTools,
        editPreviousPlan: true,
      );
    } else {
      await _executePlan(serverTools);
    }
  }

  Future<void> _executePlan(List<gemini.Tool> serverTools) async {
    // If assigned then it is used as the next input from the user
    // instead of reading from stdin.
    String? continuation =
        'Execute the plan. After each step of the plan, report your progress.';

    while (true) {
      final nextMessage = continuation ?? await stdinQueue.next;
      continuation = null;
      _addToHistory(nextMessage);
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
            final result = await _handleFunctionCall(part);
            if (result == null ||
                result.contains('unsupported response type')) {
              // Something went wrong. TODO: handle this.
            } else {
              continuation =
                  '$result\n. Please proceed to the next step of the plan.';
            }
          default:
            print('Unrecognized response type from the model $modelResponse');
        }
      }
    }
  }

  Future<String> _waitForInputAndAddToHistory() async {
    final input = await stdinQueue.next;
    chatHistory.add(gemini.Content.text(input));
    return input;
  }

  void _addToHistory(String content) {
    chatHistory.add(gemini.Content.text(content));
  }

  /// Analyzes a user [message] to see if it looks like they approved of the
  /// previous action.
  Future<bool> _analyzeSentiment(String message) async {
    if (message == 'y' || message == 'yes') return true;
    final sentimentResult =
        (await model.generateContent([
          gemini.Content.text(
            'Analyze the sentiment of the following response. If the response '
            'indicates a need for any changes, then this is not an approval. '
            'If you are highly confident that the user approves of running the '
            'previous action then respond with a single character "y".',
          ),
          gemini.Content.text(message),
        ])).candidates.single.content;
    final response = StringBuffer();
    for (var part in sentimentResult.parts.whereType<gemini.TextPart>()) {
      response.write(part.text.trim());
    }
    return response.toString() == 'y';
  }

  /// Prints `text` and adds it to the chat history
  void _chatToUser(String text) {
    final content = gemini.Content.text(text);
    final dashText = StringBuffer();
    for (var part in content.parts.whereType<gemini.TextPart>()) {
      dashText.write(part.text);
    }
    print('\n$dashText\n');
    chatHistory.add(
      gemini.Content.model([gemini.TextPart(dashText.toString())]),
    );
  }

  /// Handles a function call response from the model.
  Future<String?> _handleFunctionCall(gemini.FunctionCall functionCall) async {
    _chatToUser(
      'I am going to run the ${functionCall.name} tool with args '
      '${jsonEncode(functionCall.args)} to perform this task.',
    );

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
    return response.toString();
  }

  /// Connects us to a local [WorkflowChatBotServer].
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
    WorkflowChatBotServer(this, channel: serverChannel);
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

final class WorkflowChatBotServer extends MCPServer with ToolsSupport {
  final WorkflowClient client;

  WorkflowChatBotServer(this.client, {required super.channel})
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

final systemInstructions = gemini.Content.system('''
You are a developer assistant for Dart and Flutter apps. You are an expert
software developer.

You can help developers by connecting into the live state of their apps, helping
them with all aspects of the software development lifecycle.

If a user asks about an error in the app, you should have several tools
available to you to aid in debugging, so make sure to use those.

When a user asks you to complete a task, make a plan, which may involve multiple
steps and the use of tools available to you, and report that to the user before
you start proceeding.
''');
