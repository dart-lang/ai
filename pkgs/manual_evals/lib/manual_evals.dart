// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Support for skills that evaluate AI agents, such as loading agent
/// conversation transcripts.
library;

export 'src/check.dart' show checkTranscriptFormat;
export 'src/loading.dart'
    show
        defaultTranscriptSources,
        loadConversationTree,
        loadTranscript,
        resolveConversationId;
export 'src/sources/antigravity.dart' show AntigravityTranscriptSource;
export 'src/transcript.dart'
    show
        ConversationTranscript,
        ConversationTree,
        StepSource,
        StepStatus,
        StepType,
        ToolResult,
        TranscriptNotFoundException,
        TranscriptSource,
        TranscriptStep,
        TranscriptWarning,
        pairToolResults;

/// Placeholder function for manual evaluations.
void runManualEval(List<String> args) {
  print('Running manual eval with args: $args');
}
