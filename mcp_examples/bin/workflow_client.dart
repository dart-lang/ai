// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:async/async.dart';
import 'package:cli_util/cli_logging.dart';
import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/stdio.dart';
import 'package:google_generative_ai/google_generative_ai.dart' as gemini;

/// The list of Gemini models that are accepted as a "--model" argument.
/// Defaults to the first one in the list.
const List<String> allowedGeminiModels = ['gemini-2.5-pro', 'gemini-2.5-flash'];

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
  if (parsedArgs.wasParsed('help')) {
    print(argParser.usage);
    exit(0);
  }
  final serverCommands = parsedArgs['server'] as List<String>;
  final logger = Logger.standard();
  final logFilePath = parsedArgs.option('log');
  runZonedGuarded(
    () {
      WorkflowClient(
        serverCommands,
        geminiApiKey: geminiApiKey,
        verbose: parsedArgs.flag('verbose'),
        dtdUri: parsedArgs.option('dtd'),
        model: parsedArgs.option('model')!,
        persona: parsedArgs.flag('dash') ? _dashPersona : null,
        logger: logger,
        logFile: logFilePath != null ? File(logFilePath) : null,
      );
    },
    (exception, stack) {
      logger.stderr('$exception\n$stack\n');
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
      ..addOption(
        'log',
        abbr: 'l',
        help:
            'If specified, will create the given log file and log server '
            'traffic and diagnostic messages.',
      )
      ..addFlag('dash', help: 'Use the Dash mascot persona.', defaultsTo: false)
      ..addOption(
        'dtd',
        help: 'Pass the DTD URI to use for this workflow session.',
      )
      ..addOption(
        'model',
        defaultsTo: allowedGeminiModels.first,
        allowed: allowedGeminiModels,
        help: 'Pass the name of the model to use to run inferences.',
      )
      ..addFlag('help', abbr: 'h', help: 'Print the usage for this command.');

final class WorkflowClient extends MCPClient with RootsSupport {
  WorkflowClient(
    this.serverCommands, {
    required String geminiApiKey,
    required String model,
    required this.logger,
    String? dtdUri,
    this.verbose = false,
    String? persona,
    File? logFile,
  }) : model = gemini.GenerativeModel(
         model: model,
         apiKey: geminiApiKey,
         systemInstruction: systemInstructions(persona: persona),
       ),
       stdinQueue = StreamQueue(
         stdin.transform(utf8.decoder).transform(const LineSplitter()),
       ),
       super(Implementation(name: 'Gemini workflow client', version: '0.1.0')) {
    logSink = _createLogSink(logFile);
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
        'URIs to absolute using this root. For tools that want a root, use '
        'this URI.',
      ),
    );
    if (dtdUri != null) {
      chatHistory.add(
        gemini.Content.text(
          'If you need to establish a Dart Tooling Daemon (DTD) connection, '
          'use this URI: $dtdUri.',
        ),
      );
    }
    _startChat();
  }

  final Logger logger;
  Sink<String>? logSink;
  int totalInputTokens = 0;
  int totalOutputTokens = 0;
  final StreamQueue<String> stdinQueue;
  final List<String> serverCommands;
  final List<ServerConnection> serverConnections = [];
  final Map<String, ServerConnection> connectionForFunction = {};
  final List<gemini.Content> chatHistory = [];
  final gemini.GenerativeModel model;
  final bool verbose;

  Sink<String>? _createLogSink(File? logFile) {
    if (logFile == null) {
      return null;
    }
    Sink<String>? logSink;
    logFile.createSync(recursive: true);
    final fileByteSink = logFile.openWrite(
      mode: FileMode.write,
      encoding: utf8,
    );
    logSink = fileByteSink.transform<String>(
      StreamSinkTransformer.fromHandlers(
        handleData: (String data, EventSink<List<int>> innerSink) {
          innerSink.add(utf8.encode(data));
        },
        handleError: (
          Object error,
          StackTrace stackTrace,
          EventSink<List<int>> innerSink,
        ) {
          innerSink.addError(error, stackTrace);
          fileByteSink.flush();
        },
        handleDone: (EventSink<List<int>> innerSink) {
          innerSink.close();
        },
      ),
    );
    return logSink;
  }

  void _startChat() async {
    if (serverCommands.isNotEmpty) {
      await _connectToServers();
    }
    await _initializeServers();
    _listenToLogs();
    final serverTools = await _listServerCapabilities();

    // Introduce yourself.
    _addToHistory('Please introduce yourself and explain how you can help.');
    final introResponse = await _generateContent(
      context: chatHistory,
      tools: serverTools,
    );
    await _handleModelResponse(introResponse);

    while (true) {
      final next = await _waitForInputAndAddToHistory();

      // Remember where the history starts for this workflow
      final historyStartIndex = chatHistory.length;
      final summary = await _makeAndExecutePlan(next, serverTools);

      // Workflow/Plan execution finished, now summarize and clean up context.
      if (historyStartIndex < chatHistory.length) {
        // Remove the entire history.
        chatHistory.removeRange(historyStartIndex, chatHistory.length);
      }

      // Add the summary to the chat history.
      await _handleModelResponse(summary);
    }
  }

  /// Handles a response from the [model].
  ///
  /// If this function returns a [String], then it should be fed back into the
  /// model as a user message in order to continue the conversation.
  Future<String?> _handleModelResponse(gemini.Content response) async {
    String? continuation;
    for (var part in response.parts) {
      switch (part) {
        case gemini.TextPart():
          _chatToUser(part.text);
        case gemini.FunctionCall():
          await _handleFunctionCall(part);
          continuation = 'Please proceed to the next step of the plan.';
        default:
          logger.stderr(
            'Unrecognized response type from the model: $response.',
          );
      }
    }
    return continuation;
  }

  /// Executes a plan and returns a summary of it.
  Future<gemini.Content> _makeAndExecutePlan(
    String userPrompt,
    List<gemini.Tool> serverTools, {
    bool editPreviousPlan = false,
  }) async {
    final instruction =
        editPreviousPlan
            ? 'Edit the previous plan with the following changes:'
            : 'Create a new plan for the following task:';
    final planPrompt =
        '$instruction\n$userPrompt\n\n After you have made a '
        'plan, ask the user if they wish to proceed or if they want to make '
        'any changes to your plan.';
    _addToHistory(planPrompt);

    final planResponse = await _generateContent(
      context: chatHistory,
      tools: serverTools,
    );
    await _handleModelResponse(planResponse);

    final userResponse = await _waitForInputAndAddToHistory();
    final wasApproval = await _analyzeSentiment(userResponse);
    return wasApproval
        ? await _executePlan(serverTools)
        : await _makeAndExecutePlan(
          userResponse,
          serverTools,
          editPreviousPlan: true,
        );
  }

  /// Executes a plan and returns a summary of it.
  Future<gemini.Content> _executePlan(List<gemini.Tool> serverTools) async {
    // If assigned then it is used as the next input from the user
    // instead of reading from stdin.
    String? continuation =
        'Execute the plan. After each step of the plan, report your progress. '
        'When you are completely done executing the plan, say exactly '
        '"Workflow complete" followed by a summary of everything that was done '
        'so you can remember it for future tasks.';

    while (true) {
      final nextMessage = continuation ?? await stdinQueue.next;
      continuation = null;
      _addToHistory(nextMessage);
      final modelResponse = await _generateContent(
        context: chatHistory,
        tools: serverTools,
      );
      if (modelResponse.parts.first case final gemini.TextPart text) {
        if (text.text.toLowerCase().contains('workflow complete')) {
          return modelResponse;
        }
      }

      continuation = await _handleModelResponse(modelResponse);
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
    if (message.toLowerCase() == 'y' || message.toLowerCase() == 'yes') {
      return true;
    }
    final sentimentResult = await _generateContent(
      context: [
        gemini.Content.text(
          'Analyze the sentiment of the following response. If the response '
          'indicates a need for any changes, then this is not an approval. '
          'If you are highly confident that the user approves of running the '
          'previous action then respond with a single character "y". '
          'Otherwise respond with "n".',
        ),
        gemini.Content.text(message),
      ],
    );
    final response = StringBuffer();
    for (var part in sentimentResult.parts.whereType<gemini.TextPart>()) {
      response.write(part.text.trim());
    }
    return response.toString().toLowerCase() == 'y';
  }

  Future<gemini.Content> _generateContent({
    required Iterable<gemini.Content> context,
    List<gemini.Tool>? tools,
  }) async {
    final progress = logger.progress('thinking');
    gemini.GenerateContentResponse? response;
    try {
      response = await model.generateContent(context, tools: tools);
      return response.candidates.single.content;
    } on gemini.GenerativeAIException catch (e) {
      return gemini.Content.model([gemini.TextPart('Error: $e')]);
    } finally {
      if (response != null) {
        final inputTokens = response.usageMetadata?.promptTokenCount;
        final outputTokens = response.usageMetadata?.candidatesTokenCount;
        totalInputTokens += inputTokens ?? 0;
        totalOutputTokens += outputTokens ?? 0;
        progress.finish(
          message:
              '(input token usage: $totalInputTokens (+$inputTokens), output '
              'token usage: $totalOutputTokens (+$outputTokens))',
          showTiming: true,
        );
      } else {
        progress.finish(message: 'failed', showTiming: true);
      }
    }
  }

  /// Prints `text` and adds it to the chat history
  void _chatToUser(String text) {
    final content = gemini.Content.text(text);
    final dashText = StringBuffer();
    for (var part in content.parts.whereType<gemini.TextPart>()) {
      dashText.write(part.text);
    }
    logger.stdout('\n$dashText');
    // Add the non-personalized text to the context as it might lose some
    // useful info.
    chatHistory.add(gemini.Content.model([gemini.TextPart(text)]));
  }

  /// Handles a function call response from the model.
  ///
  /// Invokes a function and adds the result as context to the chat history.
  Future<void> _handleFunctionCall(gemini.FunctionCall functionCall) async {
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
    chatHistory.add(
      gemini.Content.functionResponse(functionCall.name, {
        'output': response.toString(),
      }),
    );
  }

  /// Connects to all servers using [serverCommands].
  Future<void> _connectToServers() async {
    for (var server in serverCommands) {
      final parts = server.split(' ');
      try {
        final process = await Process.start(
          parts.first,
          parts.skip(1).toList(),
        );
        serverConnections.add(
          connectServer(
            stdioChannel(input: process.stdout, output: process.stdin),
            protocolLogSink: logSink,
          )..done.then((_) => process.kill()),
        );
      } catch (e) {
        logger.stderr('Failed to connect to server $server: $e');
      }
    }
  }

  /// Initialization handshake.
  Future<void> _initializeServers() async {
    // Use a copy of the list to allow removal during iteration
    final connectionsToInitialize = List.of(serverConnections);
    for (var connection in connectionsToInitialize) {
      final result = await connection.initialize(
        InitializeRequest(
          protocolVersion: ProtocolVersion.latestSupported,
          capabilities: capabilities,
          clientInfo: implementation,
        ),
      );
      final serverName = connection.serverInfo?.name ?? 'server';
      if (!result.protocolVersion!.isSupported) {
        logger.stderr(
          'Protocol version mismatch for $serverName, '
          'expected a version between ${ProtocolVersion.oldestSupported} and '
          '${ProtocolVersion.latestSupported}, but got '
          '${result.protocolVersion}. Disconnecting.',
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
        final logServerName = connection.serverInfo?.name ?? '?';
        logger.stdout(
          'Server Log ($logServerName/${event.level.name}): '
          '${event.logger != null ? '[${event.logger}] ' : ''}${event.data}',
        );
      });
    }
  }

  /// Lists all the tools available the [serverConnections].
  Future<List<gemini.Tool>> _listServerCapabilities() async {
    final functions = <gemini.FunctionDeclaration>[];
    for (var connection in serverConnections) {
      final response = await connection.listTools();
      for (var tool in response.tools) {
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
    return functions.isEmpty
        ? []
        : [gemini.Tool(functionDeclarations: functions)];
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
      case JsonType.string
          when (inputSchema as StringSchema).enumValues == null:
        return gemini.Schema.string(
          description: inputSchema.description,
          nullable: nullable,
        );
      case JsonType.string
          when (inputSchema as StringSchema).enumValues != null:
      case JsonType.enumeration: // ignore: deprecated_member_use
        final schema = inputSchema as StringSchema;
        return gemini.Schema.enumString(
          enumValues: schema.enumValues!.toList(),
          description: description,
          nullable: nullable,
        );
      case JsonType.list:
        final listSchema = inputSchema as ListSchema;
        final itemSchema =
            listSchema.items == null
                ?
                // A bit of a hack here, gemini requires item schemas, just fall
                // back on string.
                gemini.Schema.string()
                : _schemaToGeminiSchema(listSchema.items!);
        return gemini.Schema.array(
          description: description,
          items: itemSchema,
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
