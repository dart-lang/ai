// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'api.dart';

extension ListPromptsRequestChecks on Subject<ListPromptsRequest> {}

extension ListPromptsResultChecks on Subject<ListPromptsResult> {
  Subject<List<Prompt>> get prompts => has((x) => x.prompts, 'prompts');
}

extension GetPromptRequestChecks on Subject<GetPromptRequest> {
  Subject<String> get name => has((x) => x.name, 'name');
  Subject<Map<String, Object?>?> get arguments =>
      has((x) => x.arguments, 'arguments');
}

extension GetPromptResultChecks on Subject<GetPromptResult> {
  Subject<String?> get description => has((x) => x.description, 'description');
  Subject<List<PromptMessage>> get messages =>
      has((x) => x.messages, 'messages');
}

extension PromptChecks on Subject<Prompt> {
  Subject<String?> get description => has((x) => x.description, 'description');
  Subject<List<PromptArgument>?> get arguments =>
      has((x) => x.arguments, 'arguments');
  Subject<List<Icon>?> get icons => has((x) => x.icons, 'icons');
}

extension PromptArgumentChecks on Subject<PromptArgument> {
  Subject<String?> get description => has((x) => x.description, 'description');
  Subject<bool?> get required => has((x) => x.required, 'required');
}

extension PromptMessageChecks on Subject<PromptMessage> {
  Subject<Role> get role => has((x) => x.role, 'role');
  Subject<Content> get content => has((x) => x.content, 'content');
}

extension PromptListChangedNotificationChecks
    on Subject<PromptListChangedNotification> {}
