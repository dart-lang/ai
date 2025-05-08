// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert'; // Added for base64Decode

import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart' as gemini;
// Assuming all necessary classes are exported by client.dart or available via ServerConnection
import 'package:dart_mcp/client.dart';

const String _apiKey = String.fromEnvironment('GEMINI_API_KEY');

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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (_apiKey.isEmpty) {
    throw ArgumentError(
      'To run this app, you need to pass in your Gemini API key using '
      '--dart-define=GEMINI_API_KEY=YOUR_API_KEY',
    );
  }

  runApp(const ChatApp());
}

class ChatApp extends StatelessWidget {
  const ChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dash Chat',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const ChatScreen(),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;

  ChatMessage({required this.text, required this.isUser});
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<ServerConnection> serverConnections = [];
  final Map<String, ServerConnection> _connectionForFunction = {}; // Added

  // Define capabilities for the client
  final clientCapabilities = ClientCapabilities(roots: RootsCapabilities());

  final client = MyMCPClient(
    ClientImplementation(name: 'Flutter Chat App', version: '1.0.0'),
  );
  final TextEditingController _textController = TextEditingController();
  final List<ChatMessage> _messages = [];
  gemini.GenerativeModel? _model;
  // gemini.ChatSession? _chat; // Replaced by _modelChatHistory
  bool _isLoading = false;

  // final List<gemini.Content> _initialHistory = [ // Renamed and integrated
  final List<gemini.Content> _modelChatHistory = [
    gemini.Content.text('The current working directory is ${Uri.base}'),
  ];

  @override
  void initState() {
    super.initState();
    if (_apiKey.isNotEmpty) {
      _model = gemini.GenerativeModel(
        model: 'gemini-2.5-pro-preview-03-25',
        apiKey: _apiKey,
        systemInstruction: systemInstructions(),
      );
      _initialGreeting();
      _startMcpServers();
      client.addRoot(
        Root(uri: Uri.base.toString(), name: 'The current working dir'),
      );
    } else {
      setState(() {
        _messages.add(
          ChatMessage(
            text:
                'GEMINI_API_KEY is not set. Please provide it to use the chat.',
            isUser: false,
          ),
        );
      });
    }
  }

  // Converted _schemaToGeminiSchema to a method within _ChatScreenState
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

  // Added _getServerTools method
  Future<List<gemini.Tool>> _getServerTools() async {
    final functions = <gemini.FunctionDeclaration>[];
    _connectionForFunction.clear(); // Clear previous mappings
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
          _connectionForFunction[tool.name] = connection;
          print(
            'Registered tool: ${tool.name} from ${connection.serverInfo?.name}',
          );
        }
      } catch (e) {
        print(
          'Error listing tools for ${connection.serverInfo?.name ?? 'a server'}: $e',
        );
      }
    }
    return functions.isEmpty
        ? []
        : [gemini.Tool(functionDeclarations: functions)];
  }

  // Added _handleFunctionCall method
  Future<void> _handleFunctionCall(gemini.FunctionCall functionCall) async {
    print('Handling function call: ${functionCall.name}');
    _modelChatHistory.add(gemini.Content.model([functionCall]));
    final connection = _connectionForFunction[functionCall.name];

    if (connection == null) {
      print('Error: No connection found for function ${functionCall.name}');
      _modelChatHistory.add(
        gemini.Content.functionResponse(functionCall.name, {
          'output':
              'Error: No connection found for function ${functionCall.name}',
        }),
      );
      return;
    }

    try {
      final result = await connection.callTool(
        CallToolRequest(name: functionCall.name, arguments: functionCall.args),
      );
      final responseBuffer = StringBuffer();

      for (var content in result.content) {
        switch (content) {
          case final TextContent textContent when textContent.isText:
            responseBuffer.writeln(textContent.text);
          case final ImageContent imageContent when imageContent.isImage:
            // Assuming _modelChatHistory is accessible and correctly typed
            _modelChatHistory.add(
              gemini.Content.data(
                imageContent.mimeType,
                base64Decode(imageContent.data),
              ),
            );
            responseBuffer.writeln('Image added to context');
          default:
            responseBuffer.writeln(
              'Got unsupported response type ${content.type}',
            );
        }
      }
      _modelChatHistory.add(
        gemini.Content.functionResponse(functionCall.name, {
          'output': responseBuffer.toString(),
        }),
      );
    } catch (e) {
      print('Error calling tool ${functionCall.name}: $e');
      _modelChatHistory.add(
        gemini.Content.functionResponse(functionCall.name, {
          'output':
              'Error executing tool ${functionCall.name}: ${e.toString()}',
        }),
      );
    }
  }

  void _initialGreeting() async {
    if (_model == null) return;

    setState(() {
      _isLoading = true;
    });

    _modelChatHistory.add(
      gemini.Content.text(
        'Please introduce yourself and explain how you can help based on your current setup.',
      ),
    );

    try {
      // Tools might not be fully ready here, but good to pass empty list if so.
      final serverTools = await _getServerTools();
      final response = await _model!.generateContent(
        _modelChatHistory, // Use the temporary history for greeting
        tools: serverTools,
      );
      final modelResponseText = response.text;

      if (modelResponseText != null) {
        setState(() {
          _messages.add(ChatMessage(text: modelResponseText, isUser: false));
        });
        // Add model's greeting to the main history
        _modelChatHistory.add(
          gemini.Content.model([gemini.TextPart(modelResponseText)]),
        );
      } else {
        setState(() {
          _messages.add(ChatMessage(text: "Ready.", isUser: false));
        });
        _modelChatHistory.add(
          gemini.Content.model([gemini.TextPart("Ready.")]),
        );
      }
    } catch (e) {
      final errorMessage = "Error with initial greeting: ${e.toString()}";
      setState(() {
        _messages.add(ChatMessage(text: errorMessage, isUser: false));
      });
      _modelChatHistory.add(
        gemini.Content.model([gemini.TextPart(errorMessage)]),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _startMcpServers() async {
    final serversToStart = [
      [
        'dart',
        '/Users/jakemac/ai/pkgs/dart_mcp/example/file_system_server.dart',
      ],
      ['dart', '/Users/jakemac/ai/pkgs/dart_tooling_mcp_server/bin/main.dart'],
    ];

    for (var serverConfig in serversToStart) {
      try {
        final connection = await client.connectStdioServer(
          serverConfig.first,
          serverConfig.skip(1).toList(),
        );
        serverConnections.add(connection);

        final initResult = await connection.initialize(
          InitializeRequest(
            protocolVersion: ProtocolVersion.latestSupported,
            capabilities: clientCapabilities,
            clientInfo: client.implementation,
          ),
        );

        final serverName = connection.serverInfo?.name ?? 'unknown';
        if (initResult.protocolVersion != ProtocolVersion.latestSupported) {
          print(
            'Protocol version mismatch for $serverName, expected ${ProtocolVersion.latestSupported}, got ${initResult.protocolVersion}. Disconnecting.',
          );
          await connection.shutdown();
          serverConnections.remove(connection);
        } else {
          connection.notifyInitialized(InitializedNotification());
          print('MCP Server $serverName initialized.');

          if (connection.serverCapabilities.logging != null) {
            final logLevel =
                LoggingLevel.info; // Changed to info from debug for less noise
            print('Setting log level to ${logLevel.name} for $serverName');
            connection.setLogLevel(SetLevelRequest(level: logLevel));
            connection.onLog.listen((event) {
              print(
                '[$serverName-log/${event.level.name}] ${event.logger != null ? '[${event.logger}] ' : ''}${event.data}',
              );
            });
          }
        }
      } catch (e, s) {
        print('Failed to start or initialize MCP server $e\n$s');
      }
    }
    // After servers are started, it's a good time to update tools for initial greeting or next message.
    await _getServerTools();
  }

  Future<void> _processModelResponse(
    gemini.GenerateContentResponse response,
  ) async {
    String? modelResponseText;
    bool functionCalled = false;

    for (var part in response.candidates.single.content.parts) {
      switch (part) {
        case gemini.TextPart():
          modelResponseText = (modelResponseText ?? "") + part.text;
          break;
        case gemini.FunctionCall():
          await _handleFunctionCall(part);
          functionCalled = true;
          break;
        default:
          print('Unrecognized response part type from the model: $part');
      }
    }

    if (modelResponseText != null && modelResponseText.isNotEmpty) {
      _addMessageToUI(modelResponseText, isUser: false);
      _modelChatHistory.add(
        gemini.Content.model([gemini.TextPart(modelResponseText)]),
      );
    } else if (!functionCalled && modelResponseText == null) {
      _addMessageToUI(
        "Sorry, I couldn't get a response or the response was empty.",
        isUser: false,
      );
      _modelChatHistory.add(
        gemini.Content.model([gemini.TextPart("No response text.")]),
      );
    }

    if (functionCalled) {
      // If a function was called, we need to send the results back to the model
      // to get the final textual response.
      if (_model != null) {
        setState(() {
          _isLoading = true;
        }); // Show loading for the follow-up
        try {
          final serverTools =
              await _getServerTools(); // Refresh tools just in case
          final followUpResponse = await _model!.generateContent(
            _modelChatHistory, // Send the whole history including the function response
            tools: serverTools,
          );
          await _processModelResponse(
            followUpResponse,
          ); // Recursively process the new response
        } catch (e) {
          final errorMessage = "Error after function call: ${e.toString()}";
          _addMessageToUI(errorMessage, isUser: false);
          _modelChatHistory.add(
            gemini.Content.model([gemini.TextPart(errorMessage)]),
          );
        } finally {
          //isLoading is handled by the recursive call or final state
        }
      }
    }
  }

  void _addMessageToUI(String text, {required bool isUser}) {
    setState(() {
      _messages.add(ChatMessage(text: text, isUser: isUser));
    });
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty || _model == null) return;

    _addMessageToUI(text, isUser: true);
    _modelChatHistory.add(gemini.Content.text(text));
    _textController.clear();

    setState(() {
      _isLoading = true;
    });

    try {
      final serverTools = await _getServerTools();
      print(
        'Sending message to model with ${serverTools.isNotEmpty ? serverTools.first.functionDeclarations?.length ?? 0 : 0} tools.',
      );
      final response = await _model!.generateContent(
        _modelChatHistory,
        tools: serverTools,
      );
      await _processModelResponse(response);
    } catch (e) {
      print('Error sending message or processing response: $e');
      final errorMessage = "An error occurred: ${e.toString()}";
      _addMessageToUI(errorMessage, isUser: false);
      _modelChatHistory.add(
        gemini.Content.model([gemini.TextPart(errorMessage)]),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dash Chat')),
      body: Column(
        children: <Widget>[
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8.0),
              reverse: true,
              itemCount: _messages.length,
              itemBuilder: (_, int index) {
                final message = _messages[_messages.length - 1 - index];
                return _buildMessageBubble(message);
              },
            ),
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: LinearProgressIndicator(),
            ),
          const Divider(height: 1.0),
          Container(
            decoration: BoxDecoration(color: Theme.of(context).cardColor),
            child: _buildTextComposer(),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    final messageBubble = Container(
      margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
      padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 14.0),
      decoration: BoxDecoration(
        color:
            message.isUser
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(16.0),
      ),
      child: Text(
        message.text,
        style: TextStyle(
          color:
              message.isUser
                  ? Theme.of(context).colorScheme.onPrimary
                  : Theme.of(context).colorScheme.onSecondaryContainer,
        ),
      ),
    );

    final iconBubble = CircleAvatar(
      backgroundColor:
          message.isUser
              ? Theme.of(context).colorScheme.secondary
              : Theme.of(context).colorScheme.primary,
      child: Text(
        message.isUser ? 'you' : 'dash',
        style: TextStyle(
          color:
              message.isUser
                  ? Theme.of(context).colorScheme.onSecondary
                  : Theme.of(context).colorScheme.onPrimary,
          fontSize: 12.0,
        ),
      ),
    );

    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment:
            CrossAxisAlignment.end, // To align bubble and avatar nicely
        children:
            message.isUser
                ? <Widget>[
                  messageBubble,
                  const SizedBox(width: 8.0),
                  iconBubble,
                ]
                : <Widget>[
                  iconBubble,
                  const SizedBox(width: 8.0),
                  messageBubble,
                ],
      ),
    );
  }

  Widget _buildTextComposer() {
    return IconTheme(
      data: IconThemeData(color: Theme.of(context).colorScheme.primary),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        child: Row(
          children: <Widget>[
            Flexible(
              child: TextField(
                controller: _textController,
                onSubmitted: _isLoading ? null : _sendMessage,
                decoration: const InputDecoration.collapsed(
                  hintText: 'Send a message',
                ),
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 4.0),
              child: IconButton(
                icon: const Icon(Icons.send),
                onPressed:
                    _isLoading
                        ? null
                        : () => _sendMessage(_textController.text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class MyMCPClient = MCPClient with RootsSupport;
