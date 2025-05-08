// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert'; // Added for base64Decode
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart' as gemini;
import 'package:dart_mcp/client.dart';

import 'api_key_service.dart' as api_key_service; // New import
import 'models/chat_message.dart';
import 'services/gemini_config.dart';
import 'services/mcp_client.dart';
import 'widgets/message_bubble.dart';
import 'widgets/text_composer.dart';

// const String _apiKey = String.fromEnvironment('GEMINI_API_KEY'); // Removed

class ChatScreen extends StatefulWidget {
  final VoidCallback onToggleTheme;

  const ChatScreen({super.key, required this.onToggleTheme});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final client = MyMCPClient();
  final TextEditingController _textController = TextEditingController();
  final List<ChatMessage> _messages = [];
  gemini.GenerativeModel? _model;
  bool _isLoading = false;
  bool _isDashMode = true;
  String? _currentApiKey; // New state variable for API key

  List<gemini.Content> _modelChatHistory = [
    gemini.Content.text('The current working directory is ${Uri.base}'),
  ];

  @override
  void initState() {
    super.initState();
    _loadApiKeyAndInitializeChat();
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
    // Ensure context is available and mounted before showing dialog
    if (!mounted) return;

    final newApiKey = await showDialog<String>(
      context: context,
      barrierDismissible: false, // User must interact with the dialog
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
                Navigator.of(context).pop(); // Close dialog, returning null
              },
            ),
            TextButton(
              child: const Text('Save'),
              onPressed: () {
                if (apiKeyController.text.isNotEmpty) {
                  Navigator.of(
                    context,
                  ).pop(apiKeyController.text); // Close dialog, returning key
                } else {
                  // Optionally, show an error message or disable save button
                  // For now, we just don't close the dialog if key is empty.
                  // Or, you could pop with a special value indicating an error.
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
          _isLoading = false; // Ensure loading indicator is off
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
        _isLoading = true; // Start loading now that we have a key
      });
    }

    _reInitializeModel();
    await _initialGreeting(); // Make sure this is awaited if it has async operations
    await _startMcpServers(); // Make sure this is awaited

    if (mounted) {
      setState(() {
        _isLoading = false; // Stop loading after initialization
      });
    }
  }

  void _reInitializeModel() {
    if (_currentApiKey == null || _currentApiKey!.isEmpty) {
      print("Error: API Key is not available. Model cannot be initialized.");
      if (mounted) {
        setState(() {
          _model = null; // Ensure model is null if API key is missing
        });
      }
      return;
    }
    // _isLoading state will be managed by the calling function
    _model = gemini.GenerativeModel(
      model: 'gemini-2.5-pro-preview-03-25',
      apiKey: _currentApiKey!, // Use the state variable
      systemInstruction:
          _isDashMode
              ? systemInstructions(persona: dashPersona)
              : systemInstructions(),
    );
  }

  // Changed to void as _initialGreeting is void
  void _toggleMode() async {
    // Made async to await _initializeChatFeatures
    if (mounted) {
      setState(() {
        _isLoading = true;
        _isDashMode = !_isDashMode;
        _messages.clear();
        _modelChatHistory = [
          gemini.Content.text('The current working directory is ${Uri.base}'),
        ];
      });
    }
    // Instead of direct re-init, go through the full initialization
    // which includes API key check and model re-initialization.
    // This also ensures that if the API key was removed or became invalid,
    // the app would prompt for it again or handle it gracefully.
    // However, _initializeChatFeatures also calls _initialGreeting and _startMcpServers,
    // which might be undesired on just a mode toggle.
    // For now, let's stick to a more direct re-initialization of the model + greeting.

    _reInitializeModel(); // Re-initialize model with new system instructions
    if (_model != null) {
      await _initialGreeting(); // Re-fetch initial greeting
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
          gemini.Content.text('The current working directory is ${Uri.base}'),
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

  Future<void> _initialGreeting() async {
    // Made async
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
    // isLoading is managed by the calling function
    // finally {
    //   if (mounted && _isLoading) {
    //     setState(() {
    //       _isLoading = false;
    //     });
    //   }
    // }
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
        final file = File('transcripts/server_$i.log');
        if (!await file.exists()) {
          await file.create(recursive: true);
        }
        await file.writeAsString('');
        final connection = await client.connectStdioServer(
          serverConfig.first,
          serverConfig.skip(1).toList(),
          protocolLogSink: file.asStringSink,
        );
        await client.initializeServer(connection);
      } catch (e) {
        print('Failed to start or initialize MCP server $e');
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
      } else if (!functionCalled &&
          (modelResponseText == null || modelResponseText.isEmpty)) {
        _addMessageToUI(
          "Sorry, I couldn\\'t get a response or the response was empty.",
          isUser: false,
        );
        _modelChatHistory.add(
          gemini.Content.model([gemini.TextPart("No response text.")]),
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

  // Changed from Future<void> to void for onSubmitted compatibility
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
          // Potentially add a button to re-trigger API key prompt if needed
          // For example, if _currentApiKey is null.
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
            SwitchListTile(
              title: Text(_isDashMode ? 'Dash Mode' : 'Gemini Mode'),
              subtitle: Text(
                _isDashMode ? 'Chat with Dash!' : 'General AI Assistant',
              ),
              value: _isDashMode,
              onChanged: (bool value) async {
                // Made onChanged async
                Navigator.pop(context);
                _toggleMode(); // Await the toggle mode
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
              // New option to change/update API Key
              leading: const Icon(Icons.vpn_key),
              title: const Text('Update API Key'),
              onTap: () async {
                Navigator.pop(context); // Close the drawer
                await _promptForApiKey(); // Call the prompt
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
              // Disable text input if API key is missing
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
