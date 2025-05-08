// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert'; // Added for base64Decode
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart' as gemini;
import 'package:dart_mcp/client.dart';

import 'models/chat_message.dart'; // New import
import 'services/gemini_config.dart'; // New import
import 'services/mcp_client.dart'; // New import
import 'widgets/message_bubble.dart'; // New import
import 'widgets/text_composer.dart'; // New import

const String _apiKey = String.fromEnvironment('GEMINI_API_KEY');

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
  bool _isLoading = false;

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
        systemInstruction: systemInstructions(persona: dashPersona),
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
      final serverTools = await _getServerTools();
      final response = await _model!.generateContent(
        _modelChatHistory,
        tools: serverTools,
      );
      final modelResponseText = response.text;

      if (modelResponseText != null) {
        setState(() {
          _messages.add(ChatMessage(text: modelResponseText, isUser: false));
        });
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

    var i = 0;
    for (var serverConfig in serversToStart) {
      try {
        final file = File('transcripts/server_${i++}.log');
        if (!await file.exists()) {
          await file.create(recursive: true);
        }
        await file.writeAsString('');
        final connection = await client.connectStdioServer(
          serverConfig.first,
          serverConfig.skip(1).toList(),
          protocolLogSink: file.asStringSink,
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
            'Protocol version mismatch for $serverName, expected '
            '${ProtocolVersion.latestSupported}, got '
            '${initResult.protocolVersion}. Disconnecting.',
          );
          await connection.shutdown();
          serverConnections.remove(connection);
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
        }
      } catch (e, s) {
        print('Failed to start or initialize MCP server $e\n$s');
      }
    }
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
      if (_model != null) {
        setState(() {
          _isLoading = true;
        });
        try {
          final serverTools = await _getServerTools();
          final followUpResponse = await _model!.generateContent(
            _modelChatHistory,
            tools: serverTools,
          );
          await _processModelResponse(followUpResponse);
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
      body: Column(
        children: <Widget>[
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8.0),
              reverse: true,
              itemCount: _messages.length,
              itemBuilder: (_, int index) {
                final message = _messages[_messages.length - 1 - index];
                // Use the new MessageBubble widget
                return MessageBubble(message: message);
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
            // Use the new TextComposer widget
            child: TextComposer(
              textController: _textController,
              isLoading: _isLoading,
              onSubmitted: _sendMessage,
            ),
          ),
        ],
      ),
    );
  }
}
