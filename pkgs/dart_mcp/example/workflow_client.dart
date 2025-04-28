// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:async/async.dart';
import 'package:dart_mcp/client.dart';
import 'package:google_generative_ai/google_generative_ai.dart' as gemini;

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
  runZonedGuarded(
    () {
      WorkflowClient(
        serverCommands,
        geminiApiKey: geminiApiKey,
        verbose: parsedArgs.flag('verbose'),
        dtdUri: parsedArgs.option('dtd'),
        persona: parsedArgs.flag('dash') ? _dashPersona : null,
      );
    },
    (e, s) {
      stderr.writeln('$e\n$s');
    },
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
      )
      ..addFlag('dash', help: 'Use the Dash mascot persona.', defaultsTo: false)
      ..addOption(
        'dtd',
        help: 'Pass the DTD URI to use for this workflow session.',
      );

final class WorkflowClient extends MCPClient with RootsSupport {
  WorkflowClient(
    this.serverCommands, {
    required String geminiApiKey,
    String? dtdUri,
    this.verbose = false,
    String? persona,
  }) : model = gemini.GenerativeModel(
         model: 'gemini-2.5-pro-preview-03-25',
         // model: 'gemini-2.0-flash',
         //  model: 'gemini-2.5-flash-preview-04-17',
         apiKey: geminiApiKey,
         systemInstruction: systemInstructions(persona: persona),
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
    chatHistory.add(
      gemini.Content.text(
        'The current working directory is '
        '${Directory.current.absolute.uri.toString()}. Convert all relative '
        'URIs to absolute using this root. For tools that want a root, use this'
        'URI.',
      ),
    );
    if (dtdUri != null) {
      chatHistory.add(
        gemini.Content.text(
          'Connect to the Dart Tooling Daemon (DTD) at $dtdUri.',
        ),
      );
    }
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

    while (true) {
      final next = await _waitForInputAndAddToHistory();
      await _makeAndExecutePlan(next, serverTools);
    }
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
            ? 'Edit the previous plan with the following changes:'
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
              _chatToUser(
                'Something went wrong when trying to call the ${part.name} '
                'function. Proceeding to next step of the plan.',
              );
            }
            continuation =
                '$result\n. Please proceed to the next step of the plan.';

          default:
            print('Unrecognized response type from the model: $modelResponse.');
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
      'I am going to run the ${functionCall.name} tool'
      '${verbose ? ' with args ${jsonEncode(functionCall.args)}' : ''} to '
      'perform this task.',
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

final _dashPersona = '''
You are a cute blue hummingbird named Dash, and you are also the mascot for the
Dart and Flutter brands. Your personality is cheery and bright, and your tone is
always positive.
''';

/// If a [persona] is passed, it will be added to the system prompt as its own
/// paragraph.
gemini.Content systemInstructions({String? persona}) =>
    gemini.Content.system('''
You are a developer assistant for Dart and Flutter apps. You are an expert
software developer.
${persona != null ? '\n$persona\n' : ''}
You can help developers with writing code by generating Dart and Flutter code or
making changes to their existing app. You can also help developers with
debugging their code by connecting into the live state of their apps, helping
them with all aspects of the software development lifecycle.

If a user asks about an error or a widget in the app, you should have several
tools available to you to aid in debugging, so make sure to use those.

If a user asks for code that requires adding or removing a dependency, you have
several tools available to you for managing pub dependencies.

If a user asks you to complete a task that requires writing to files, only edit
the part of the file that is required. After you apply the edit, the file should
contain all of the contents it did before with the changes you made applied.
After editing files, always fix any errors and perform a hot reload to apply the
changes.

When a user asks you to complete a task, you should first make a plan, which may
involve multiple steps and the use of tools available to you. Report this plan
back to the user before proceeding.

Generally, if you are asked to make code changes, you should follow this high
level process:

1) Write the code and apply the changes to the codebase
2) Check for static analysis errors and warnings and fix them
3) Check for runtime errors and fix them
4) Ensure that all code is formatted properly
5) Hot reload the changes to the running app

If, while executing your plan, you end up skipping steps because they are no
longer applicable, explain why you are skipping them.
''');
