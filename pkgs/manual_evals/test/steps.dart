// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Builders for transcript steps and transcripts, for tests.
library;

import 'package:manual_evals/manual_evals.dart';

/// A transcript for [conversationId] with [steps], numbered in order.
ConversationTranscript transcript(
  List<Map<String, Object?>> steps, {
  String conversationId = 'conv',
}) => ConversationTranscript(
  conversationId: conversationId,
  path: conversationId,
  steps: [
    for (final (index, step) in steps.indexed)
      TranscriptStep({'step_index': index, ...step}),
  ],
  subagentIds: [],
);

/// A `USER_INPUT` step for [request], wrapped the way the runtime wraps it.
Map<String, Object?> userInput(String request) => {
  'type': 'USER_INPUT',
  'source': 'USER_EXPLICIT',
  'content':
      '<USER_REQUEST>\n$request\n</USER_REQUEST>\n'
      '<ADDITIONAL_METADATA>\nThe user is: someone.\n</ADDITIONAL_METADATA>',
};

/// A `PLANNER_RESPONSE` step that records the given token counts, [thinking],
/// and [content], and makes the tool [calls] (see [toolCall]).
Map<String, Object?> modelCall({
  int? input,
  int? cacheRead,
  int? output,
  String? thinking,
  String? content,
  List<Object?> calls = const [],
}) => {
  'type': 'PLANNER_RESPONSE',
  'source': 'MODEL',
  'input_tokens': ?input,
  'cache_read_tokens': ?cacheRead,
  'output_tokens': ?output,
  'thinking': ?thinking,
  'content': ?content,
  'tool_calls': calls,
};

/// A call to the tool [name], with [args] if given, for [modelCall].
Map<String, Object?> toolCall(String name, [Map<String, Object?>? args]) => {
  'name': name,
  'args': ?args,
};

/// A tool result step with [content].
Map<String, Object?> toolResult(String content) => {
  'type': 'GENERIC',
  'source': 'MODEL',
  'content': content,
};

/// A `SYSTEM_MESSAGE` step with [content].
Map<String, Object?> systemMessage(String content) => {
  'type': 'SYSTEM_MESSAGE',
  'source': 'SYSTEM',
  'content': content,
};

/// An `ERROR_MESSAGE` step with [content], which answers a tool call that
/// couldn't be run.
Map<String, Object?> errorMessage([String content = '']) => {
  'type': 'ERROR_MESSAGE',
  'source': 'SYSTEM',
  'content': content,
};

/// A `SYSTEM_MESSAGE` step delivering a runtime message from [sender] with
/// [content], wrapped the way the runtime wraps it.
Map<String, Object?> runtimeMessage(String sender, String content) =>
    systemMessage(
      'The following is a <SYSTEM_MESSAGE> not actually sent by the user.\n'
      '\n'
      '<SYSTEM_MESSAGE>\n'
      '[Message] timestamp=2026-01-01T00:00:00Z sender=$sender '
      'priority=MESSAGE_PRIORITY_HIGH content=$content\n'
      '</SYSTEM_MESSAGE>',
    );
