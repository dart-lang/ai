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
/// and [content], and calls [tools] without arguments followed by [calls].
Map<String, Object?> modelCall({
  int? input,
  int? cacheRead,
  int? output,
  String? thinking,
  String? content,
  List<String> tools = const [],
  List<Map<String, Object?>> calls = const [],
}) => {
  'type': 'PLANNER_RESPONSE',
  'source': 'MODEL',
  'input_tokens': ?input,
  'cache_read_tokens': ?cacheRead,
  'output_tokens': ?output,
  'thinking': ?thinking,
  'content': ?content,
  'tool_calls': [
    for (final name in tools) {'name': name},
    ...calls,
  ],
};

/// A call to the tool [name] with [args], for [modelCall].
Map<String, Object?> toolCall(
  String name, [
  Map<String, Object?> args = const {},
]) => {'name': name, 'args': args};

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
