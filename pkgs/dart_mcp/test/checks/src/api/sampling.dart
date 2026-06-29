// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'api.dart';

extension CreateMessageRequestChecks on Subject<CreateMessageRequest> {
  Subject<List<SamplingMessage>> get messages =>
      has((x) => x.messages, 'messages');
  Subject<ModelPreferences?> get modelPreferences =>
      has((x) => x.modelPreferences, 'modelPreferences');
  Subject<String?> get systemPrompt =>
      has((x) => x.systemPrompt, 'systemPrompt');
  Subject<IncludeContext?> get includeContext =>
      has((x) => x.includeContext, 'includeContext');
  Subject<double?> get temperature => has((x) => x.temperature, 'temperature');
  Subject<int> get maxTokens => has((x) => x.maxTokens, 'maxTokens');
  Subject<List<String>?> get stopSequences =>
      has((x) => x.stopSequences, 'stopSequences');
  Subject<ToolChoice?> get toolChoice => has((x) => x.toolChoice, 'toolChoice');
  Subject<Map<String, Object?>?> get metadata =>
      has((x) => x.metadata, 'metadata');
}

extension CreateMessageResultChecks on Subject<CreateMessageResult> {
  Subject<String> get model => has((x) => x.model, 'model');
  Subject<String?> get stopReason => has((x) => x.stopReason, 'stopReason');
}

extension SamplingMessageChecks<T extends SamplingMessage> on Subject<T> {
  Subject<Role> get role => has((x) => x.role, 'role');
  Subject<Content> get content =>
      has((x) => x.content, 'content');
}

extension ModelPreferencesChecks on Subject<ModelPreferences> {
  Subject<List<ModelHint>?> get hints => has((x) => x.hints, 'hints');
  Subject<double?> get costPriority =>
      has((x) => x.costPriority, 'costPriority');
  Subject<double?> get speedPriority =>
      has((x) => x.speedPriority, 'speedPriority');
  Subject<double?> get intelligencePriority =>
      has((x) => x.intelligencePriority, 'intelligencePriority');
}

extension ModelHintChecks on Subject<ModelHint> {
  Subject<String?> get name => has((x) => x.name, 'name');
}

extension ToolChoiceChecks on Subject<ToolChoice> {
  Subject<ToolChoiceMode> get mode => has((x) => x.mode, 'mode');
}
