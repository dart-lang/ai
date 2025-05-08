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

import 'models/chat_message.dart'; // New import
import 'services/gemini_config.dart'; // New import
import 'services/mcp_client.dart'; // New import
import 'widgets/message_bubble.dart'; // New import
import 'widgets/text_composer.dart'; // New import

const String _apiKey = String.fromEnvironment('GEMINI_API_KEY');

class ChatScreen extends StatefulWidget {
  final VoidCallback onToggleTheme; // Added callback for theme toggle

  const ChatScreen({
    super.key,
    required this.onToggleTheme,
  }); // Updated constructor

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final client = MyMCPClient();
  final TextEditingController _textController = TextEditingController();
  final List<ChatMessage> _messages = [];
  gemini.GenerativeModel? _model;
  bool _isLoading = false;
  bool _isDashMode = true; // Added for mode toggle

  List<gemini.Content> _modelChatHistory = [
    gemini.Content.text('The current working directory is ${Uri.base}'),
  ];

  @override
  void initState() {
    super.initState();
    if (_apiKey.isNotEmpty) {
      _reInitializeModel();
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

  void _reInitializeModel() {
    if (_apiKey.isEmpty) return;
    // _isLoading state will be managed by the calling function (initState or _toggleMode)
    _model = gemini.GenerativeModel(
      model: 'gemini-2.5-pro-preview-03-25',
      apiKey: _apiKey,
      systemInstruction:
          _isDashMode
              ? systemInstructions(persona: dashPersona)
              : systemInstructions(), // No persona for Gemini mode
    );
  }

  // Changed to void as _initialGreeting is void
  void _toggleMode() {
    setState(() {
      _isLoading = true;
      _isDashMode = !_isDashMode;
      _messages.clear();
      _modelChatHistory = [
        // Reset history with initial context
        gemini.Content.text('The current working directory is ${Uri.base}'),
      ];
    });

    _reInitializeModel();
    _initialGreeting(); // Removed await, as _initialGreeting is void
  }

  void _clearChatHistory() {
    setState(() {
      _messages.clear();
      _modelChatHistory = [
        gemini.Content.text('The current working directory is ${Uri.base}'),
      ];
      // Add a message to indicate the chat has been cleared.
      _messages.add(
        ChatMessage(
          text: 'Chat history cleared.',
          isUser: false, // Or a neutral/system type if you have one
        ),
      );
    });
  }

  Future<gemini.GenerateContentResponse> _generateContentWithRetry(
    List<gemini.Content> history, {
    List<gemini.Tool>? tools,
    int maxRetries = 3,
    Duration delay = const Duration(seconds: 1),
  }) async {
    if (_model == null) {
      throw Exception("Model is not initialized.");
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

  void _initialGreeting() async {
    if (_model == null) {
      if (mounted && _isLoading) {
        setState(() {
          _isLoading = false;
        });
      }
      return;
    }

    if (mounted && !_isLoading) {
      setState(() {
        _isLoading = true;
      });
    }

    // Add the standard greeting prompt, ensuring it\\\'s not duplicated if already there
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
    } finally {
      if (mounted && _isLoading) {
        setState(() {
          _isLoading = false;
        });
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
      // Corrected loop to use i
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
        // Removed unused stack trace s
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
          "Sorry, I couldn't get a response or the response was empty.",
          isUser: false,
        );
        _modelChatHistory.add(
          // Corrected typo: _modelChatHSICKtory to _modelChatHistory
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
      }
    }
  }

  void _addMessageToUI(String text, {required bool isUser}) {
    final trimmedText = text.trim(); // Trim the text
    if (trimmedText.isEmpty) return; // Don't add empty messages

    if (mounted) {
      setState(() {
        // Use the trimmed text to create ChatMessage
        _messages.add(ChatMessage(text: trimmedText, isUser: isUser));
      });
    }
  }

  Future<void> _sendMessage(String text) async {
    final trimmedText = text.trim(); // Trim the text early
    if (trimmedText.isEmpty || _model == null) return;

    _addMessageToUI(trimmedText, isUser: true); // Use trimmedText
    _modelChatHistory.add(gemini.Content.text(trimmedText)); // Use trimmedText
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
        title: Text(_isDashMode ? 'Dash Chat' : 'Gemini Chat'), // Dynamic title
        actions: [
          IconButton(
            icon: const Icon(Icons.brightness_6),
            onPressed: widget.onToggleTheme,
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
              onChanged: (bool value) {
                Navigator.pop(context); // Close the drawer
                _toggleMode();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Clear Chat History'),
              onTap: () {
                Navigator.pop(context); // Close the drawer
                _clearChatHistory();
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
                // Pass _isDashMode to MessageBubble
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
              onSubmitted: _sendMessage,
            ),
          ),
        ],
      ),
    );
  }
}
