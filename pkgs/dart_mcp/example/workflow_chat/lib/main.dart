import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart' as gemini;
// import 'package:dart_mcp/client.dart'; // MCP client not used in this version

// TODO: Replace with your actual API key from flutter run --dart-define=GEMINI_API_KEY=YOUR_API_KEY
const String _apiKey = String.fromEnvironment('GEMINI_API_KEY');

// System instruction similar to the one in workflow_client.dart
// It's simplified here as we are not using the full tool/planning capabilities.
gemini.Content systemInstructions() => gemini.Content.system('''
You are a developer assistant for Dart and Flutter apps. You are an expert
software developer.

You can help developers with writing code by generating Dart and Flutter code or
making changes to their existing app.
''');

void main() {
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
      title: 'Flutter Chat Client',
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
  final bool
  isUser; // true if the message is from the user, false for the model

  ChatMessage({required this.text, required this.isUser});
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final List<ChatMessage> _messages = [];
  gemini.GenerativeModel? _model;
  gemini.ChatSession? _chat;
  bool _isLoading = false;

  // Store initial history content, similar to workflow_client.dart
  final List<gemini.Content> _initialHistory = [
    gemini.Content.text(
      'The current working directory is file:///Users/jakemac/ai/pkgs/dart_mcp/example/workflow_chat/ '
      'Convert all relative URIs to absolute using this root. For tools that want a root, use this URI.',
    ),
    // Note: DTD URI is not included here as it was for tool usage in the original client.
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
      // Start chat with the initial history
      _chat = _model?.startChat(
        history: _initialHistory.toList(),
      ); // Use a copy
      _initialGreeting();
    } else {
      // Display an error message in the chat if API key is missing
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

  void _initialGreeting() async {
    if (_chat != null) {
      setState(() {
        _isLoading = true;
      });
      try {
        final response = await _chat!.sendMessage(
          gemini.Content.text(
            'Please introduce yourself and explain how you can help based on your current setup.',
          ),
        );
        final modelResponseText = response.text;
        if (modelResponseText != null) {
          setState(() {
            _messages.add(ChatMessage(text: modelResponseText, isUser: false));
          });
        } else {
          _messages.add(ChatMessage(text: "Ready.", isUser: false));
        }
      } catch (e) {
        _messages.add(
          ChatMessage(
            text: "Error with initial greeting: \${e.toString()}",
            isUser: false,
          ),
        );
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true));
      _isLoading = true;
    });
    _textController.clear();

    if (_chat == null) {
      setState(() {
        _messages.add(
          ChatMessage(
            text:
                "Error: Chat session not initialized. Did you provide an API key?",
            isUser: false,
          ),
        );
        _isLoading = false;
      });
      return;
    }

    try {
      final response = await _chat!.sendMessage(gemini.Content.text(text));
      final modelResponseText = response.text; // response.text is nullable

      if (modelResponseText != null && modelResponseText.isNotEmpty) {
        setState(() {
          _messages.add(ChatMessage(text: modelResponseText, isUser: false));
        });
      } else {
        // Handle cases where the response might be empty or only contain function calls (not applicable here)
        setState(() {
          _messages.add(
            ChatMessage(
              text:
                  "Sorry, I couldn't get a response or the response was empty.",
              isUser: false,
            ),
          );
        });
      }
    } catch (e) {
      // ignore: avoid_print
      print('Error sending message: $e');
      setState(() {
        _messages.add(
          ChatMessage(
            text: "An error occurred: ${e.toString()}",
            isUser: false,
          ),
        );
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Moved API key check to initState for cleaner build method
    // and to allow showing an error message within the chat UI.
    return Scaffold(
      appBar: AppBar(title: const Text('Flutter Chat Client')),
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
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
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
