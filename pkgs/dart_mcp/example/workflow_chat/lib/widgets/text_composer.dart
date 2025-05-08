import 'package:flutter/material.dart';

class TextComposer extends StatelessWidget {
  final TextEditingController textController;
  final bool isLoading;
  final Function(String) onSubmitted;

  const TextComposer({
    super.key,
    required this.textController,
    required this.isLoading,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return IconTheme(
      data: IconThemeData(color: Theme.of(context).colorScheme.primary),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        child: Row(
          children: <Widget>[
            Flexible(
              child: TextField(
                controller: textController,
                onSubmitted: isLoading ? null : onSubmitted,
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
                    isLoading ? null : () => onSubmitted(textController.text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
