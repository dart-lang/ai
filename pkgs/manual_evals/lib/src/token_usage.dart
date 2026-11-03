// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'transcript.dart';

/// Token counts for one or more model calls, as recorded by the agent
/// runtime.
final class const TokenCounts({
  /// Input tokens that were not read from the cache.
  final int input = 0,

  /// Input tokens that were read from the cache.
  final int cacheRead = 0,

  /// Output tokens, including reasoning.
  final int output = 0,
}) {
  /// No tokens.
  static const zero = TokenCounts();

  /// All recorded input and output tokens.
  ///
  /// Tokens written to the cache aren't recorded, so this can be lower than
  /// the number of tokens the model processed.
  int get total => input + cacheRead + output;

  /// The sum of these counts and [other].
  TokenCounts operator +(TokenCounts other) => TokenCounts(
    input: input + other.input,
    cacheRead: cacheRead + other.cacheRead,
    output: output + other.output,
  );
}

/// The model calls made in response to one user request.
final class const TurnUsage({
  /// The text of the user request that started the turn, on one line, or
  /// `null` for model calls made before the first user request.
  required final String? request,

  /// The number of model calls in the turn.
  required final int modelCalls,

  /// The tokens used by the turn's model calls.
  required final TokenCounts tokens,
});

/// The calls to one tool and the size of their results.
final class const ToolUsage({
  /// The number of calls.
  required final int calls,

  /// The total length of the results' content.
  required final int resultCharacters,
});

/// The token usage of one conversation, not including its subagents.
final class ConversationUsage({
  /// The ID of the conversation.
  required final String conversationId,
  required List<TurnUsage> turns,
  required Map<String, ToolUsage> tools,

  /// The number of model calls that didn't record token usage, which are
  /// counted in [modelCalls] but not in [tokens].
  final int unrecordedModelCalls = 0,
}) {
  /// The conversation's turns, in order.
  final List<TurnUsage> turns = List.unmodifiable(turns);

  /// The usage of each tool the conversation called, by tool name, in the
  /// order the tools were first called.
  final Map<String, ToolUsage> tools = Map.unmodifiable(tools);

  /// The number of model calls in the conversation.
  int get modelCalls => turns.fold(0, (sum, turn) => sum + turn.modelCalls);

  /// The tokens used by the conversation's model calls.
  TokenCounts get tokens =>
      turns.fold(TokenCounts.zero, (sum, turn) => sum + turn.tokens);
}

/// Measures the token usage of [transcript] from the counts recorded on its
/// model calls.
///
/// A turn starts at each [StepType.userInput] step.
ConversationUsage measureTokenUsage(ConversationTranscript transcript) {
  final turns = <TurnUsage>[];
  String? request;
  var modelCalls = 0;
  var tokens = TokenCounts.zero;
  var unrecordedModelCalls = 0;
  final toolCalls = <String, int>{};

  void endTurn() {
    if (modelCalls == 0 && request == null) return;
    turns.add(
      TurnUsage(request: request, modelCalls: modelCalls, tokens: tokens),
    );
    modelCalls = 0;
    tokens = TokenCounts.zero;
  }

  for (final step in transcript.steps) {
    if (step.type == StepType.userInput) {
      endTurn();
      request = step.userRequest;
    } else if (step.type == StepType.plannerResponse) {
      modelCalls++;
      if (!step.recordsTokenUsage) unrecordedModelCalls++;
      tokens += TokenCounts(
        input: step.inputTokens ?? 0,
        cacheRead: step.cacheReadTokens ?? 0,
        output: step.outputTokens ?? 0,
      );
      for (final name in step.toolCallNames) {
        final tool = _toolName(name);
        toolCalls[tool] = (toolCalls[tool] ?? 0) + 1;
      }
    }
  }
  endTurn();

  final resultCharacters = <String, int>{};
  for (final (:toolName, :step) in pairToolResults(transcript.steps)) {
    final tool = _toolName(toolName);
    resultCharacters[tool] =
        (resultCharacters[tool] ?? 0) + step.content.length;
  }

  return ConversationUsage(
    conversationId: transcript.conversationId,
    turns: turns,
    tools: {
      for (final MapEntry(key: tool, value: calls) in toolCalls.entries)
        tool: ToolUsage(
          calls: calls,
          resultCharacters: resultCharacters[tool] ?? 0,
        ),
    },
    unrecordedModelCalls: unrecordedModelCalls,
  );
}

/// The name to report for a tool call named [name], which is `null` if the
/// call is malformed.
String _toolName(String? name) => name ?? '(unknown)';
