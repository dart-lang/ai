// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Support for skills that evaluate AI agents, such as loading agent
/// conversation transcripts.
library;

export 'src/check.dart' show checkTranscriptFormat;
export 'src/command.dart' show loadConversationTreeFromArgs;
export 'src/loading.dart'
    show
        defaultTranscriptSources,
        loadConversationTree,
        loadTranscript,
        resolveConversationId;
export 'src/sources/antigravity.dart' show AntigravityTranscriptSource;
export 'src/token_report.dart' show formatTokenReport;
export 'src/token_usage.dart'
    show
        ConversationUsage,
        TokenCounts,
        ToolUsage,
        TurnUsage,
        measureTokenUsage;
export 'src/trajectory.dart'
    show
        ToolOutcome,
        Trajectory,
        TrajectoryToolCall,
        TrajectoryTurn,
        TurnTrigger,
        summarizeTrajectory;
export 'src/trajectory_report.dart' show formatTrajectoryReport;
export 'src/transcript.dart'
    show
        ConversationTranscript,
        ConversationTree,
        StepSource,
        StepStatus,
        StepType,
        ToolCallAnswer,
        ToolResult,
        TranscriptNotFoundException,
        TranscriptSource,
        TranscriptStep,
        TranscriptWarning,
        pairToolCalls,
        pairToolResults;

/// Placeholder function for manual evaluations.
void runManualEval(List<String> args) {
  print('Running manual eval with args: $args');
}
