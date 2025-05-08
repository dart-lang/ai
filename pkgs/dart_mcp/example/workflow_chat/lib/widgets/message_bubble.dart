// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

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

    final Widget iconBubble;
    if (message.isUser) {
      iconBubble = CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.secondary,
        child: Text(
          'you',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSecondary,
            fontSize: 12.0,
          ),
        ),
      );
    } else {
      iconBubble = SizedBox(
        width: 40.0,
        height: 40.0,
        child: Padding(
          padding: const EdgeInsets.all(4.0),
          child: Image.asset('assets/dash.png'),
        ),
      );
    }

    final transformedIcon = Transform.translate(
      offset: const Offset(0, -4.0),
      child: iconBubble,
    );

    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end, // Set back to end
        children:
            message.isUser
                ? <Widget>[
                  Expanded(child: messageBubble),
                  const SizedBox(width: 8.0),
                  transformedIcon, // Use the transformed icon
                ]
                : <Widget>[
                  transformedIcon, // Use the transformed icon
                  const SizedBox(width: 8.0),
                  Expanded(child: messageBubble),
                ],
      ),
    );
  }
}
