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
  final TextEditingController _dtdUriController =
      TextEditingController(); // Added DTD URI controller
  final List<ChatMessage> _messages = [];
  gemini.GenerativeModel? _model;
  bool _isLoading = false;
  bool _isDashMode = true; // Default value, will be overridden by preferences
  String? _currentApiKey; // New state variable for API key
  String? _dtdUri; // Added DTD URI state variable

  List<gemini.Content> _modelChatHistory = []; // Initialized in initState

  @override
  void initState() {
    super.initState();
    client = MyMCPClient(projectUri: widget.projectPath);
    _initializeScreen();
  }

  @override
  void dispose() {
    _textController.dispose();
    _dtdUriController.dispose(); // Dispose DTD URI controller
    super.dispose();
  }

  Future<void> _initializeScreen() async {
    await _loadDashModePreference();
    await _loadDtdUri();
    await _loadApiKeyAndInitializeChat();
  }

  void _resetModelChatHistory() {
    final initialContext = <gemini.Content>[
      gemini.Content.text(
        'The current working directory is ${widget.projectPath} use this for '
        'all file operations.',
      ),
      if (_dtdUri?.isNotEmpty == true)
        gemini.Content.text(
          'The DTD URI is $_dtdUri, use this to connect to DTD.',
        ),
      gemini.Content.text(
        "When checking for runtime errors, don't clear them first. You should "
        "clear them as a part of reading them so that you don't see the same "
        "errors later on.",
      ),
      gemini.Content.text(
        'Please introduce yourself and explain how you can help based on your '
        'current setup.',
      ),
    ];

    _modelChatHistory = initialContext;
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

  Future<void> _loadDtdUri() async {
    final prefs = await SharedPreferences.getInstance();
    final String? savedDtdUri = prefs.getString('dtdUri');
    if (mounted) {
      setState(() {
        _dtdUri = savedDtdUri;
        _dtdUriController.text = _dtdUri ?? ''; // Initialize controller text
      });
      if (_dtdUri != null && _dtdUri!.isNotEmpty) {
        print('DTD URI loaded: $_dtdUri');
      }
    }
  }

  Future<void> _saveDtdUri(String uri) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('dtdUri', uri);
    if (mounted) {
      setState(() {
        final oldUri = _dtdUri;
        _dtdUri = uri;
        _dtdUriController.text = uri;
        if (oldUri != uri) {
          _modelChatHistory.add(gemini.Content.text('The DTD URI is $_dtdUri'));
        }
      });
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            uri.isEmpty ? 'DTD URI cleared.' : 'DTD URI saved: $uri',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _promptForDtdUri() async {
    if (mounted) {
      _dtdUriController.text = _dtdUri ?? '';
    }

    final newDtdUri = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Set DTD URI'),
          content: TextField(
            controller: _dtdUriController,
            decoration: const InputDecoration(
              hintText: "ws://127.0.0.1:xxxxx/",
            ),
            autofocus: true,
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
                Navigator.of(context).pop(_dtdUriController.text);
              },
            ),
          ],
        );
      },
    );

    if (newDtdUri != null) {
      await _saveDtdUri(newDtdUri);
    }
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
        _resetModelChatHistory();
        _addMessageToUI(
          'API Key is required to use the chat. Please set an API Key.',
          isUser: false,
        );
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _initializeChatFeatures() async {
    if (_currentApiKey == null || _currentApiKey!.isEmpty) {
      if (mounted) {
        _resetModelChatHistory(); // Ensure history is reset
        _addMessageToUI(
          'Cannot initialize chat: API Key is missing.',
          isUser: false,
        );
        setState(() {
          _isLoading = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    _reInitializeModel(); // This sets up _model based on _currentApiKey and _isDashMode
    _resetModelChatHistory(); // This now sets the initial history with prompts
    await _initialGreeting(); // This sends the history to the model
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
        _messages.clear(); // Clear UI messages
      });
      await _saveDashModePreference(_isDashMode);
    }

    _reInitializeModel(); // Re-init model for new mode (applies new system instruction)
    _resetModelChatHistory(); // Reset history for the new mode, includes intro prompt

    if (_model != null) {
      await _initialGreeting(); // Get new greeting for the new mode
    } else {
      if (mounted) {
        _addMessageToUI(
          'Failed to switch mode: API Key might be missing.',
          isUser: false,
        );
      }
    }
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Helper to clear UI messages and reset model history.
  // Useful when DTD URI changes or chat is manually cleared.
  void _clearMessagesAndResetHistory() {
    if (mounted) {
      setState(() {
        _messages.clear();
      });
    }
    _resetModelChatHistory();
  }

  void _clearChatHistory() {
    _clearMessagesAndResetHistory();
    if (mounted) {
      // Add a confirmation message to the UI after clearing.
      _addMessageToUI('Chat history cleared.', isUser: false);
      // The _initialGreeting is NOT called here by default,
      // to give a sense of a truly "cleared" state.
      // The next user message will use the fresh context.
      // If a re-greeting is desired, _initialGreeting() could be called here.
      setState(() {
        _isLoading = false; // Ensure loading indicator is off
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
        _addMessageToUI(
          "Error: Model is not initialized. API key might be missing.",
          isUser: false,
        );
        setState(() => _isLoading = false);
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
      dynamic decodedOutput = responseBuffer.toString();
      try {
        decodedOutput = jsonDecode(decodedOutput);
      } catch (_) {
        // It's not JSON, use as plain text
      }

      _modelChatHistory.add(
        gemini.Content.functionResponse(functionCall.name, {
          'output': decodedOutput,
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
    if (_model == null) {
      if (mounted) {
        _addMessageToUI(
          "Cannot greet you: API Key is missing or model not initialized.",
          isUser: false,
        );
        setState(() => _isLoading = false);
      }
      return;
    }

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
      if (mounted) {
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
      final candidate = response.candidates.first;
      for (var part in candidate.content.parts) {
        switch (part) {
          case gemini.TextPart():
            _modelChatHistory.add(gemini.Content.model([part]));
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
            // Only turn off if this was the last op
            final lastPart = _modelChatHistory.lastOrNull?.parts.lastOrNull;
            if (lastPart is! gemini.FunctionCall) {
              // if the model's last response was not another function call
              setState(() {
                _isLoading = false;
              });
            }
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
    } else if (mounted && _isLoading && !functionCalled) {
      // If no function was called and we were loading, stop loading.
      setState(() {
        _isLoading = false;
      });
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
      // _processModelResponse will handle setting _isLoading to false
      // unless an error occurs before it's called or at its very end.
      if (mounted && _isLoading) {
        // Check if the very last part of the conversation isn't a function call
        // If it is, _processModelResponse will handle the loading state.
        final lastPart = _modelChatHistory.lastOrNull?.parts.lastOrNull;
        if (lastPart is! gemini.FunctionCall) {
          setState(() {
            _isLoading = false;
          });
        }
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
            ListTile(
              // Added DTD URI ListTile
              leading: const Icon(Icons.settings_ethernet),
              title: const Text('Set DTD URI'),
              subtitle: Text(_dtdUri ?? 'Not set'),
              onTap: () async {
                Navigator.pop(context); // Close the drawer first
                await _promptForDtdUri();
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
                        _addMessageToUI(
                          "Please set an API key to chat.",
                          isUser: false,
                        );
                      },
            ),
          ),
        ],
      ),
    );
  }
}
