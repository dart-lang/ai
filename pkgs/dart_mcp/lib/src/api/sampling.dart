// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'api.dart';

/// The types of context in which should be included in a prompt.
enum IncludeContext { none, thisService, allServers }

/// A request from the server to sample an LLM via the client.
///
/// The client has full discretion over which model to select. The client should
/// also inform the user before beginning sampling, to allow them to inspect
/// the request (human in the loop) and decide whether to approve it.
extension type CreateMessageRequest.fromMap(Map<String, Object?> _value)
    implements Request {
  static const methodName = 'sampling/createMessage';

  factory CreateMessageRequest({
    required List<SamplingMessage> messages,
    ModelPreferences? modelPreferences,
    String? systemPrompt,
    IncludeContext? includeContext,
    int? temperature,
    required int maxTokens,
    List<String>? stopSequences,
    Map<String, Object?>? metadata,
    MetaWithProgressToken? meta,
  }) => CreateMessageRequest.fromMap({
    'messages': messages,
    if (modelPreferences != null) 'modelPreferences': modelPreferences,
    if (systemPrompt != null) 'systemPrompt': systemPrompt,
    if (includeContext != null) 'includeContext': includeContext.name,
    if (temperature != null) 'temperature': temperature,
    'maxTokens': maxTokens,
    if (stopSequences != null) 'stopSequences': stopSequences,
    if (metadata != null) 'metadata': metadata,
    if (meta != null) '_meta': meta,
  });

  /// The messages to send to the LLM.
  List<SamplingMessage> get messages =>
      (_value['messages'] as List).cast<SamplingMessage>();

  /// The server's preferences for which model to select.
  ///
  /// The client MAY ignore these preferences.
  ModelPreferences? get modelPreferences =>
      _value['modelPreferences'] as ModelPreferences?;

  /// An optional system prompt the server wants to use for sampling.
  ///
  /// The client MAY modify or omit this prompt.
  String? get systemPrompt => _value['systemPrompt'] as String?;

  /// A request to include context from one or more MCP servers (including
  /// the caller), to be attached to the prompt.
  ///
  /// The client MAY ignore this request.
  IncludeContext? get includeContext {
    final includeContext = _value['includeContext'] as String?;
    if (includeContext == null) return null;
    return IncludeContext.values.firstWhere((c) => c.name == includeContext);
  }

  /// The temperature to use for sampling.
  double? get temperature => _value['temperature'] as double?;

  /// The maximum number of tokens to sample, as requested by the server.
  ///
  /// The client MAY choose to sample fewer tokens than requested.
  int get maxTokens => _value['maxTokens'] as int;

  /// Note: This has no documentation in the specification or schema.
  List<String>? get stopSequences =>
      (_value['stopSequences'] as List?)?.cast<String>();

  /// Optional metadata to pass through to the LLM provider.
  ///
  /// The format of this metadata is provider-specific.
  Map<String, Object?>? get metadata =>
      (_value['metadata'] as Map?)?.cast<String, Object?>();
}

/// The client's response to a sampling/create_message request from the
/// server.
///
/// The client should inform the user before returning the sampled message, to
/// allow them to inspect the response (human in the loop) and decide whether
/// to allow the server to see it.
extension type CreateMessageResult.fromMap(Map<String, Object?> _value)
    implements Result, SamplingMessage {
  factory CreateMessageResult({
    required Role role,
    required Content content,
    required String model,
    String? stopReason,
    Meta? meta,
  }) => CreateMessageResult.fromMap({
    'role': role.name,
    'content': content,
    'model': model,
    if (stopReason != null) 'stopReason': stopReason,
    if (meta != null) '_meta': meta,
  });

  /// The name of the model that generated the message.
  String get model => _value['model'] as String;

  /// The reason why sampling stopped, if known.
  ///
  /// Known reasons are "endTurn", "stopSequence", "maxTokens", or any other
  /// reason.
  String? get stopReason => _value['stopReason'] as String?;
}

/// Describes a message issued to or received from an LLM API.
extension type SamplingMessage.fromMap(Map<String, Object?> _value) {
  factory SamplingMessage({required Role role, required Content content}) =>
      SamplingMessage.fromMap({'role': role.name, 'content': content});

  /// The role of the message.
  Role get role =>
      Role.values.firstWhere((role) => role.name == _value['role']);

  /// The content of the message.
  Content get content => _value['content'] as Content;
}

/// The server's preferences for model selection, requested of the client
/// during sampling.
///
/// Because LLMs can vary along multiple dimensions, choosing the "best" model
/// is rarely straightforward.  Different models excel in different areas—some
/// are faster but less capable, others are more capable but more expensive,
/// and so on. This interface allows servers to express their priorities
/// across multiple dimensions to help clients make an appropriate selection
/// for their use case.
///
/// These preferences are always advisory. The client MAY ignore them. It is
/// also up to the client to decide how to interpret these preferences and
/// how to balance them against other considerations.
extension type ModelPreferences.fromMap(Map<String, Object?> _value) {
  factory ModelPreferences({
    List<ModelHint>? hints,
    double? costPriority,
    double? speedPriority,
    double? intelligencePriority,
  }) => ModelPreferences.fromMap({
    if (hints != null) 'hints': hints,
    if (costPriority != null) 'costPriority': costPriority,
    if (speedPriority != null) 'speedPriority': speedPriority,
    if (intelligencePriority != null)
      'intelligencePriority': intelligencePriority,
  });

  /// Optional hints to use for model selection.
  ///
  /// If multiple hints are specified, the client MUST evaluate them in order
  /// (such that the first match is taken).
  ///
  /// The client SHOULD prioritize these hints over the numeric priorities,
  /// but MAY still use the priorities to select from ambiguous matches.
  List<ModelHint>? get hints => (_value['hints'] as List?)?.cast<ModelHint>();

  /// How much to prioritize cost when selecting a model.
  ///
  /// A value of 0 means cost is not important, while a value of 1 means cost
  /// is the most important factor.
  double? get costPriority => _value['costPriority'] as double?;

  /// How much to prioritize sampling speed (latency) when selecting a model.
  ///
  /// A value of 0 means speed is not important, while a value of 1 means speed
  /// is the most important factor.
  double? get speedPriority => _value['speedPriority'] as double?;

  /// How much to prioritize intelligence and capabilities when selecting a
  /// model.
  ///
  /// A value of 0 means intelligence is not important, while a value of 1
  /// means intelligence is the most important factor.
  double? get intelligencePriority => _value['intelligencePriority'] as double?;
}

/// Hints to use for model selection.
///
/// Keys not declared here are currently left unspecified by the spec and are
/// up to the client to interpret.
extension type ModelHint.fromMap(Map<String, Object?> _value) {
  factory ModelHint({String? name}) =>
      ModelHint.fromMap({if (name != null) 'name': name});

  /// A hint for a model name.
  ///
  /// The client SHOULD treat this as a substring of a model name; for
  /// example:
  ///  - `claude-3-5-sonnet` should match `claude-3-5-sonnet-20241022`
  ///  - `sonnet` should match `claude-3-5-sonnet-20241022`,
  ///    `claude-3-sonnet-20240229`, etc.
  ///  - `claude` should match any Claude model
  ///
  /// The client MAY also map the string to a different provider's model name
  /// or a different model family, as long as it fills a similar niche; for
  /// example:
  ///  - `gemini-1.5-flash` could match `claude-3-haiku-20240307`
  String? get name => _value['name'] as String?;
}
