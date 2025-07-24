// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:dart_mcp/server.dart';
import 'package:meta/meta.dart';

/// A mixin which adds support for various dart and flutter specific prompts.
base mixin DashPrompts on PromptsSupport {
  @override
  FutureOr<InitializeResult> initialize(InitializeRequest request) {
    addPrompt(flutterDriverUserJourneyTest, _flutterDriverUserJourneyPrompt);
    return super.initialize(request);
  }

  /// Creates the flutter driver user journey prompt based on a request.
  GetPromptResult _flutterDriverUserJourneyPrompt(GetPromptRequest request) {
    return GetPromptResult(
      messages: [
        PromptMessage(
          role: Role.user,
          content: flutterDriverUserJourneyPromptContent,
        ),
      ],
    );
  }

  @visibleForTesting
  static final flutterDriverUserJourneyTest = Prompt(
    name: 'flutter_driver_user_journey_test',
    title: 'User journey flutter driver test',
    description: '''
Prompts the LLM to attempt to accomplish a user journey in the running app using
flutter driver. If successful, it will then translate the steps it followed into
a flutter driver test and write that to disk.
''',
  );

  @visibleForTesting
  static final flutterDriverUserJourneyPromptContent = Content.text(
    text: '''
Perform the following tasks in order:

- Prompt the user to navigate to the home page of the app.
- Prompt the user for a user journey that they would like to write a test for.
- Attempt to complete the given user journey using flutter driver to inspect the
  widget tree and interact with the application. Only durable interactions
  should be performed, do not use temporary IDs to select or interact with
  widgets, but instead select them based on text, type, tooltip, etc. Avoid
  reading in files to accomplish this task, just inspect the live state of the
  app and widget tree. If you get stuck, feel free to ask the user for help.
- If you are able to successfully complete the journey, then create a flutter
  driver based test with an appropriate name, which performs all the same
  actions that you performed. Include the original user journey as a comment
  in the test file.
''',
  );
}
