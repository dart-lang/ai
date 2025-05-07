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
  final logger = Logger.standard();
  runZonedGuarded(
    () {
      WorkflowClient(
        serverCommands,
        geminiApiKey: geminiApiKey,
        verbose: parsedArgs.flag('verbose'),
        dtdUri: parsedArgs.option('dtd'),
        persona: parsedArgs.flag('dash') ? _dashPersona : null,
        logger: logger,
      );
    },
    (e, s) {
      // Fixed: Use triple quotes for multi-line string
      logger.stderr('''$e
$s''');
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
  final Logger logger;
  int totalInputTokens = 0;
  int totalOutputTokens = 0;

  WorkflowClient(
    this.serverCommands, {
    required String geminiApiKey,
    String? dtdUri,
    this.verbose = false,
    required this.logger,
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
    final introResponse = await _generateContent(
      context: chatHistory,
      tools: serverTools,
    );
    await _handleModelResponse(introResponse);

    while (true) {
      final next =
          await _waitForInputAndAddToHistory(); // User provides the task prompt

      // Remember where the history starts for this workflow
      final historyStartIndex = chatHistory.length;
      final summary = await _makeAndExecutePlan(next, serverTools);

      // Workflow/Plan execution finished, now summarize.
      if (historyStartIndex < chatHistory.length) {
        // Replace the messages related to the completed workflow with the
        // summary.
        chatHistory.replaceRange(historyStartIndex, chatHistory.length, [
          summary,
        ]);

        // Let the user know the summarization happened, but don't add that
        // message to the history.
        final summaryText = summary.parts
            .whereType<gemini.TextPart>()
            .map((p) => p.text)
            .join('');
        logger.stdout('Workflow summarized: $summaryText');
      }
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
          final result = await _handleFunctionCall(part);
          if (result == null || result.contains('unsupported response type')) {
            _chatToUser(
              'Something went wrong when trying to call the ${part.name} '
              'function. Proceeding to next step of the plan.',
            );
          }
          // Fixed: Use triple quotes for multi-line string
          continuation = '''
Function result: $result

Please proceed to the next step of the plan.''';
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
    // Fixed: Use triple quotes for multi-line string
    final planPrompt = '''$instruction
$userPrompt. After you have made a plan, ask the user if they wish to proceed or if they want to make any changes to your plan.''';
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
        'When you are executing the plan, say exactly "Workflow complete" '
        'followed by a summary of everything that was done so you can remember '
        'it for future tasks.';

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
    // Fixed: Added curly braces
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
          'Otherwise respond with "n".', // Added explicit negative case
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
      // Added safety check for empty candidates
      if (response.candidates.isEmpty) {
        throw Exception('Model returned no candidates.');
      }
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
    logger.stdout('''
$dashText''');
    // Add the non-personalized text to the context as it might lose some
    // useful info.
    chatHistory.add(gemini.Content.model([gemini.TextPart(text)]));
  }

  /// Handles a function call response from the model.
  Future<String?> _handleFunctionCall(gemini.FunctionCall functionCall) async {
    chatHistory.add(gemini.Content.model([functionCall]));
    final connection = connectionForFunction[functionCall.name];
    // Added safety check for missing connection
    if (connection == null) {
      final errorMsg =
          'Error: No server connection found for function '
          '${functionCall.name}.';
      logger.stderr(errorMsg);
      chatHistory.add(
        gemini.Content.functionResponse(functionCall.name, {'error': errorMsg}),
      );
      return errorMsg;
    }

    try {
      final result = await connection.callTool(
        CallToolRequest(name: functionCall.name, arguments: functionCall.args),
      );
      final response = StringBuffer();
      final functionResponseParts =
          <gemini.Part>[]; // Collect parts for history

      for (var content in result.content) {
        switch (content) {
          case final TextContent content when content.isText:
            response.writeln(content.text);
            functionResponseParts.add(gemini.TextPart(content.text));
          case final ImageContent content when content.isImage:
            // History addition for images might need review depending on how
            // large they are and if they are useful in subsequent turns.
            // For now, adding as data.
            final dataPart = gemini.DataPart(
              content.mimeType,
              base64Decode(content.data),
            );
            // Add image directly to history for model context
            chatHistory.add(gemini.Content.model([dataPart]));
            final imageMsg =
                'Received image data (${content.mimeType}). Added to history.';
            response.writeln(imageMsg);
            // Add a text representation of the image receipt to the function
            // response part
            functionResponseParts.add(gemini.TextPart(imageMsg));
          default:
            final unsupportedMsg =
                'Got unsupported response type ${content.type}';
            response.writeln(unsupportedMsg);
            functionResponseParts.add(gemini.TextPart(unsupportedMsg));
        }
      }
      // Add the consolidated function response to history
      chatHistory.add(
        gemini.Content.functionResponse(functionCall.name, {
          'output': response.toString(),
        }),
      );
      return response.toString();
    } catch (e, s) {
      // Catch errors during tool execution
      // Fixed: Use triple quotes for multi-line string
      final errorMsg = '''Error calling tool ${functionCall.name}: $e
$s''';
      logger.stderr(errorMsg);
      chatHistory.add(
        gemini.Content.functionResponse(functionCall.name, {'error': errorMsg}),
      );
      return 'Error during tool execution: $e';
    }
  }

  /// Connects to all servers using [serverCommands].
  Future<void> _connectToServers() async {
    for (var server in serverCommands) {
      final parts = server.split(' ');
      try {
        serverConnections.add(
          await connectStdioServer(parts.first, parts.skip(1).toList()),
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
      try {
        final result = await connection.initialize(
          InitializeRequest(
            protocolVersion: ProtocolVersion.latestSupported,
            capabilities: capabilities,
            clientInfo: implementation,
          ),
        );
        final serverName = connection.serverInfo?.name ?? 'server';
        if (result.protocolVersion != ProtocolVersion.latestSupported) {
          logger.stderr(
            'Protocol version mismatch for $serverName, '
            'expected ${ProtocolVersion.latestSupported}, got '
            '${result.protocolVersion}. Disconnecting.',
          );
          await connection.shutdown();
          serverConnections.remove(connection);
        } else {
          connection.notifyInitialized(InitializedNotification());
        }
      } catch (e) {
        final failedServerName = connection.serverInfo?.name ?? 'unknown';
        logger.stderr('Failed to initialize server $failedServerName: $e');
        // Attempt shutdown on error
        await connection.shutdown().catchError((_) {});
        serverConnections.remove(connection);
      }
    }
  }

  /// Listens for log messages on all [serverConnections] that support logging.
  void _listenToLogs() {
    for (var connection in serverConnections) {
      if (connection.serverCapabilities.logging == null) {
        continue;
      }

      connection
          .setLogLevel(
            SetLevelRequest(
              level: verbose ? LoggingLevel.debug : LoggingLevel.warning,
            ),
          )
          .catchError((Object e) {
            // Fixed: Added explicit type Object
            // Catch potential errors setting log level
            final errorServerName = connection.serverInfo?.name ?? 'server';
            logger.stderr('Failed to set log level for $errorServerName: $e');
          });
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
      try {
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
      } catch (e) {
        final errorServerName = connection.serverInfo?.name ?? 'unknown';
        logger.stderr('Failed to list tools for server $errorServerName: $e');
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
                // Fix: Check if required is null before calling contains
                nullable:
                    !(objectSchema.required?.contains(entry.key) ?? false),
              ),
          };
        }
        return gemini.Schema.object(
          description: description,
          properties: properties ?? {},
          nullable: nullable,
        );
      case JsonType.string:
        // Fixed: Removed unsupported enumValues parameter/logic
        return gemini.Schema.string(
          description: inputSchema.description,
          nullable: nullable,
        );
      case JsonType.list:
        final listSchema = inputSchema as ListSchema;
        // Fix: Handle case where listSchema.items might be null
        // (though unlikely per spec)
        final itemSchema =
            listSchema.items == null
                ? gemini.Schema.string(description: 'any')
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
      // Fixed: Removed JsonType.any case
      // Consider adding null type if needed, though Gemini schema might handle
      // nullable field
      // case JsonType.nullValue:
      //    return gemini.Schema(...); // No direct null type in gemini.Schema,
      // use nullable=true
      default:
        // Fallback for safety, though ideally all types should be handled
        logger.stderr(
          'Warning: Unhandled schema type ${inputSchema.type}. '
          'Treating as string.',
        );
        return gemini.Schema.string(
          description:
              '${description ?? ''} (unhandled type: ${inputSchema.type})'
                  .trim(),
          nullable: nullable,
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
gemini.Content systemInstructions({String? persona}) => gemini.Content.system('''
You are a developer assistant for Dart and Flutter apps. You are an expert
software developer.
${persona != null ? '''

$persona
''' : ''}
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
