import 'package:flutter/material.dart';

import '../models/chat_message.dart'; // Adjusted import

class MessageBubble extends StatelessWidget {
  final ChatMessage message;

  const MessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
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
                  Expanded(child: messageBubble),
                  const SizedBox(width: 8.0),
                  iconBubble,
                ]
                : <Widget>[
                  iconBubble,
                  const SizedBox(width: 8.0),
                  Expanded(child: messageBubble),
                ],
      ),
    );
  }
}
