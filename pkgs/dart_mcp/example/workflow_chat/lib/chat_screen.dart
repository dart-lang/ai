// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert'; // Added for base64Decode and utf8
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart' as gemini;
import 'package:dart_mcp/client.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Added import

import 'api_key_service.dart' as api_key_service; // New import
import 'models/chat_message.dart';
import 'services/gemini_config.dart';
import 'services/mcp_client.dart';
import 'widgets/message_bubble.dart';
import 'widgets/text_composer.dart';

class ChatScreen extends StatefulWidget {
  final VoidCallback onToggleTheme;
  final String projectPath; // Added projectPath
  final VoidCallback onRequestNewDirectory; // Callback to request new directory

  const ChatScreen({
    super.key,
    required this.onToggleTheme,
    required this.projectPath,
    required this.onRequestNewDirectory,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final MyMCPClient client; // Initialize in initState
  final TextEditingController _textController = TextEditingController();
  final List<ChatMessage> _messages = [];
  gemini.GenerativeModel? _model;
  bool _isLoading = false;
  bool _isDashMode = true; // Default value, will be overridden by preferences
  String? _currentApiKey; // New state variable for API key

  List<gemini.Content> _modelChatHistory = []; // Initialized in initState

  @override
  void initState() {
    super.initState();
    // Initialize client with the projectUri from the widget
    client = MyMCPClient(projectUri: widget.projectPath);
    _modelChatHistory = [
      gemini.Content.text(
        'The current working directory is ${widget.projectPath}',
      ),
    ];
    _initializeScreen();
  }

  Future<void> _initializeScreen() async {
    await _loadDashModePreference();
    await _loadApiKeyAndInitializeChat();
  }

  Future<void> _loadDashModePreference() async {
    final prefs = await SharedPreferences.getInstance();
    final bool savedIsDashMode = prefs.getBool('isDashMode') ?? true;
    if (mounted) {
      setState(() {
        _isDashMode = savedIsDashMode;
      });
    }
  }

  Future<void> _saveDashModePreference(bool isDashMode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDashMode', isDashMode);
  }

  Future<void> _loadApiKeyAndInitializeChat() async {
    final String? storedApiKey = await api_key_service.getApiKey();
    if (storedApiKey != null && storedApiKey.isNotEmpty) {
      if (mounted) {
        setState(() {
          _currentApiKey = storedApiKey;
        });
        await _initializeChatFeatures();
      }
    } else {
      await _promptForApiKey();
    }
  }

  Future<void> _promptForApiKey() async {
    final apiKeyController = TextEditingController();
    if (!mounted) return;

    final newApiKey = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Enter Gemini API Key'),
          content: TextField(
            controller: apiKeyController,
            decoration: const InputDecoration(hintText: "Your API Key"),
            obscureText: true,
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Save'),
              onPressed: () {
                if (apiKeyController.text.isNotEmpty) {
                  Navigator.of(context).pop(apiKeyController.text);
                }
              },
            ),
          ],
        );
      },
    );

    if (newApiKey != null && newApiKey.isNotEmpty) {
      await api_key_service.saveApiKey(newApiKey);
      if (mounted) {
        setState(() {
          _currentApiKey = newApiKey;
        });
        await _initializeChatFeatures();
      }
    } else {
      if (mounted) {
        setState(() {
          _messages.add(
            ChatMessage(
              text:
                  'API Key is required to use the chat. Please restart the application or provide a key via settings (if available).',
              isUser: false,
            ),
          );
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _initializeChatFeatures() async {
    if (_currentApiKey == null || _currentApiKey!.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          if (!_messages.any(
            (msg) => msg.text.startsWith('API Key is required'),
          )) {
            _messages.add(
              ChatMessage(
                text: 'Cannot initialize chat: API Key is missing.',
                isUser: false,
              ),
            );
          }
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    _reInitializeModel();
    await _initialGreeting();
    await _startMcpServers();

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _reInitializeModel() {
    if (_currentApiKey == null || _currentApiKey!.isEmpty) {
      print("Error: API Key is not available. Model cannot be initialized.");
      if (mounted) {
        setState(() {
          _model = null;
        });
      }
      return;
    }
    _model = gemini.GenerativeModel(
      model: 'gemini-2.5-pro-preview-03-25',
      apiKey: _currentApiKey!,
      systemInstruction:
          _isDashMode
              ? systemInstructions(persona: dashPersona)
              : systemInstructions(),
    );
  }

  void _toggleMode() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _isDashMode = !_isDashMode;
        _messages.clear();
        _modelChatHistory = [
          gemini.Content.text(
            'The current working directory is ${widget.projectPath}',
          ),
        ];
      });
      await _saveDashModePreference(_isDashMode);
    }

    _reInitializeModel();
    if (_model != null) {
      await _initialGreeting();
    } else {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _messages.add(
            ChatMessage(
              text: 'Failed to switch mode: API Key might be missing.',
              isUser: false,
            ),
          );
        });
      }
    }
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _clearChatHistory() {
    if (mounted) {
      setState(() {
        _messages.clear();
        _modelChatHistory = [
          gemini.Content.text(
            'The current working directory is ${widget.projectPath}',
          ),
        ];
        _messages.add(
          ChatMessage(text: 'Chat history cleared.', isUser: false),
        );
      });
    }
  }

  Future<gemini.GenerateContentResponse> _generateContentWithRetry(
    List<gemini.Content> history, {
    List<gemini.Tool>? tools,
    int maxRetries = 3,
    Duration delay = const Duration(seconds: 1),
  }) async {
    if (_model == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          if (!_messages.any(
            (msg) => msg.text.contains('Model is not initialized'),
          )) {
            _messages.add(
              ChatMessage(
                text:
                    "Error: Model is not initialized. API key might be missing.",
                isUser: false,
              ),
            );
          }
        });
      }
      throw Exception("Model is not initialized. API key might be missing.");
    }
    int attempt = 0;
    while (attempt < maxRetries) {
      try {
        return await _model!.generateContent(history, tools: tools);
      } catch (e) {
        attempt++;
        if (attempt >= maxRetries) {
          print("Max retries reached for generateContent. Error: $e");
          rethrow;
        }
        print(
          "Attempt $attempt failed for generateContent. Retrying in $delay. Error: $e",
        );
        await Future.delayed(delay);
      }
    }
    throw Exception("Exited retry loop without success or rethrow.");
  }

  Future<void> _handleFunctionCall(gemini.FunctionCall functionCall) async {
    print('Handling function call: ${functionCall.name}');
    _modelChatHistory.add(gemini.Content.model([functionCall]));
    final connection = client.connectionForFunction[functionCall.name];

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
            try {
              _modelChatHistory.add(
                gemini.Content.data(
                  imageContent.mimeType,
                  base64Decode(imageContent.data),
                ),
              );
              responseBuffer.writeln('Image added to context');
            } catch (e) {
              print("Error decoding base64 image: $e");
              responseBuffer.writeln('Failed to process image data.');
            }
            break;
          default:
            responseBuffer.writeln(
              'Got unsupported response type ${content.type}',
            );
        }
      }
      dynamic decoded = responseBuffer.toString();
      try {
        decoded = jsonDecode(decoded);
      } catch (_) {
        // Just continue;
      }
      _modelChatHistory.add(
        gemini.Content.functionResponse(functionCall.name, {'output': decoded}),
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

  Future<void> _initialGreeting() async {
    if (_model == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          if (!_messages.any((msg) => msg.text.startsWith('Cannot greet'))) {
            _messages.add(
              ChatMessage(
                text: "Cannot greet you without an API Key!",
                isUser: false,
              ),
            );
          }
        });
      }
      return;
    }

    if (_modelChatHistory.isEmpty ||
        !(_modelChatHistory.first.parts.first is gemini.TextPart &&
            (_modelChatHistory.first.parts.first as gemini.TextPart).text ==
                'The current working directory is ${widget.projectPath}')) {
      _modelChatHistory.insert(
        0,
        gemini.Content.text(
          'The current working directory is ${widget.projectPath}',
        ),
      );
    }

    if (_modelChatHistory.length == 1 ||
        _modelChatHistory.last.role != 'user' ||
        (_modelChatHistory.last.parts.first as gemini.TextPart).text !=
            'Please introduce yourself and explain how you can help based on your current setup.') {
      _modelChatHistory.add(
        gemini.Content.text(
          'Please introduce yourself and explain how you can help based on your current setup.',
        ),
      );
    }

    try {
      final response = await _generateContentWithRetry(
        _modelChatHistory,
        tools: client.tools,
      );
      final modelResponseText = response.text;

      if (mounted) {
        if (modelResponseText != null && modelResponseText.isNotEmpty) {
          _addMessageToUI(modelResponseText, isUser: false);
          _modelChatHistory.add(
            gemini.Content.model([gemini.TextPart(modelResponseText)]),
          );
        } else {
          _addMessageToUI("Ready.", isUser: false);
          _modelChatHistory.add(
            gemini.Content.model([gemini.TextPart("Ready.")]),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        final errorMessage = "Error with initial greeting: ${e.toString()}";
        _addMessageToUI(errorMessage, isUser: false);
        _modelChatHistory.add(
          gemini.Content.model([gemini.TextPart(errorMessage)]),
        );
      }
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

    for (int i = 0; i < serversToStart.length; i++) {
      var serverConfig = serversToStart[i];
      try {
        final Directory transcriptsDir = Directory('transcripts');
        if (!await transcriptsDir.exists()) {
          await transcriptsDir.create(recursive: true);
        }
        final file = File('${transcriptsDir.path}/server_$i.log');

        await file.writeAsString('');

        final connection = await client.connectStdioServer(
          serverConfig.first,
          serverConfig.skip(1).toList(),
          protocolLogSink: file.asStringSink,
        );
        await client.initializeServer(connection);
      } catch (e) {
        print('Failed to start or initialize MCP server $e');
        if (mounted) {
          _addMessageToUI(
            'Failed to start MCP server: ${e.toString()}',
            isUser: false,
          );
        }
      }
    }
  }

  Future<void> _processModelResponse(
    gemini.GenerateContentResponse response,
  ) async {
    String? modelResponseText;
    bool functionCalled = false;

    if (response.candidates.isNotEmpty) {
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
    }

    if (mounted) {
      if (modelResponseText != null && modelResponseText.isNotEmpty) {
        _addMessageToUI(modelResponseText, isUser: false);
        _modelChatHistory.add(
          gemini.Content.model([gemini.TextPart(modelResponseText)]),
        );
      }
    }

    if (functionCalled) {
      if (_model != null) {
        if (mounted) {
          setState(() {
            _isLoading = true;
          });
        }
        try {
          final followUpResponse = await _generateContentWithRetry(
            _modelChatHistory,
            tools: client.tools,
          );
          await _processModelResponse(followUpResponse);
        } catch (e, s) {
          if (mounted) {
            final errorMessage = "Error after function call: $e\n$s";
            _addMessageToUI(errorMessage, isUser: false);
            _modelChatHistory.add(
              gemini.Content.model([gemini.TextPart(errorMessage)]),
            );
          }
        } finally {
          if (mounted && _isLoading) {
            setState(() {
              _isLoading = false;
            });
          }
        }
      } else {
        if (mounted) {
          _addMessageToUI(
            "Error: Model not available for follow-up after function call.",
            isUser: false,
          );
          setState(() => _isLoading = false);
        }
      }
    }
  }

  void _addMessageToUI(String text, {required bool isUser}) {
    final trimmedText = text.trim();
    if (trimmedText.isEmpty) return;

    if (mounted) {
      setState(() {
        _messages.add(ChatMessage(text: trimmedText, isUser: isUser));
      });
    }
  }

  void _sendMessage(String text) async {
    final trimmedText = text.trim();
    if (trimmedText.isEmpty) return;

    if (_model == null) {
      if (mounted) {
        _addMessageToUI(
          "Cannot send message: API Key is missing or model not initialized.",
          isUser: false,
        );
      }
      return;
    }

    _addMessageToUI(trimmedText, isUser: true);
    _modelChatHistory.add(gemini.Content.text(trimmedText));
    _textController.clear();

    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final response = await _generateContentWithRetry(
        _modelChatHistory,
        tools: client.tools,
      );
      await _processModelResponse(response);
    } catch (e) {
      if (mounted) {
        print('Error sending message or processing response: $e');
        final errorMessage = "An error occurred: ${e.toString()}";
        _addMessageToUI(errorMessage, isUser: false);
        _modelChatHistory.add(
          gemini.Content.model([gemini.TextPart(errorMessage)]),
        );
      }
    } finally {
      if (mounted && _isLoading) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isDashMode ? 'Dash Chat' : 'Gemini Chat'),
        actions: [
          IconButton(
            icon: const Icon(Icons.brightness_6),
            onPressed: widget.onToggleTheme,
          ),
          if (_currentApiKey == null || _currentApiKey!.isEmpty)
            IconButton(
              icon: const Icon(Icons.vpn_key_off_outlined),
              tooltip: 'Setup API Key',
              onPressed: () async {
                await _promptForApiKey();
              },
            ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: <Widget>[
            DrawerHeader(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
              ),
              child: Text(
                'Settings',
                style: TextStyle(
                  fontSize: 24,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: const Text('Change Project Directory'),
              onTap: () {
                Navigator.pop(context); // Close the drawer
                widget.onRequestNewDirectory(); // Call the callback
              },
            ),
            SwitchListTile(
              title: Text(_isDashMode ? 'Dash Mode' : 'Gemini Mode'),
              subtitle: Text(
                _isDashMode ? 'Chat with Dash!' : 'General AI Assistant',
              ),
              value: _isDashMode,
              onChanged: (bool value) async {
                Navigator.pop(context);
                _toggleMode();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Clear Chat History'),
              onTap: () {
                Navigator.pop(context);
                _clearChatHistory();
              },
            ),
            ListTile(
              leading: const Icon(Icons.vpn_key),
              title: const Text('Update API Key'),
              onTap: () async {
                Navigator.pop(context);
                await _promptForApiKey();
              },
            ),
          ],
        ),
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8.0),
              reverse: true,
              itemCount: _messages.length,
              itemBuilder: (_, int index) {
                final message = _messages[_messages.length - 1 - index];
                return MessageBubble(message: message, isDashMode: _isDashMode);
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
            child: TextComposer(
              textController: _textController,
              isLoading: _isLoading,
              onSubmitted:
                  (_currentApiKey != null && _currentApiKey!.isNotEmpty)
                      ? _sendMessage
                      : (String text) {
                        /* Do nothing, input is disabled */
                      },
            ),
          ),
        ],
      ),
    );
  }
}
