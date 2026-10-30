// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:collection';
import 'dart:io';

import 'sources/antigravity.dart';
import 'transcript.dart';

/// The transcript sources used when none are given: currently only
/// [AntigravityTranscriptSource].
List<TranscriptSource> defaultTranscriptSources() => [
  AntigravityTranscriptSource(),
];

/// Resolves the conversation ID to inspect.
///
/// Returns [conversationId], trimmed, if it isn't blank. Otherwise returns the
/// first [TranscriptSource.currentConversationId] from [sources] (which
/// defaults to [defaultTranscriptSources]), if any.
String? resolveConversationId(
  String? conversationId, {
  List<TranscriptSource>? sources,
}) {
  if (conversationId?.trim() case final id? when id.isNotEmpty) return id;
  for (final source in sources ?? defaultTranscriptSources()) {
    if (source.currentConversationId case final id?) return id;
  }
  return null;
}

/// Loads the transcript for [conversationId] from the first of [sources]
/// (which defaults to [defaultTranscriptSources]) that has it, or returns
/// `null` if none do.
///
/// Throws a `FileSystemException` if the transcript can't be read.
Future<ConversationTranscript?> loadTranscript(
  String conversationId, {
  List<TranscriptSource>? sources,
}) async =>
    (await _loadFromSources(
      conversationId,
      sources ?? defaultTranscriptSources(),
    ))?.transcript;

/// Loads the transcripts of [rootConversationId] and all the subagent
/// conversations it started, transitively.
///
/// The root is loaded from the first of [sources] (which defaults to
/// [defaultTranscriptSources]) that has it, and its subagents from the same
/// source. Each conversation is loaded once, even if it's reached more than
/// once. Subagents whose transcripts are missing or unreadable are skipped,
/// with a warning in [ConversationTree.warnings].
///
/// Throws a [TranscriptNotFoundException] if the root transcript can't be
/// found, or a `FileSystemException` if it can't be read.
Future<ConversationTree> loadConversationTree(
  String rootConversationId, {
  List<TranscriptSource>? sources,
}) async {
  final searched = sources ?? defaultTranscriptSources();
  final rootResult = await _loadFromSources(rootConversationId, searched);
  if (rootResult == null) {
    throw TranscriptNotFoundException(rootConversationId, searched);
  }
  final (:source, transcript: root) = rootResult;

  final transcripts = [root];
  final loadWarnings = <TranscriptWarning>[];
  final seen = {rootConversationId};
  final pending = Queue.of([
    for (final id in root.subagentIds) (id: id, parentId: rootConversationId),
  ]);
  while (pending.isNotEmpty) {
    final (:id, :parentId) = pending.removeFirst();
    if (!seen.add(id)) continue;
    final ConversationTranscript? transcript;
    try {
      transcript = await source.loadTranscript(id);
    } on FileSystemException catch (e) {
      loadWarnings.add(
        TranscriptWarning(
          parentId,
          "Can't read the transcript of subagent $id: ${e.message}",
        ),
      );
      continue;
    }
    if (transcript == null) {
      loadWarnings.add(
        TranscriptWarning(parentId, 'Subagent $id has no transcript.'),
      );
      continue;
    }
    transcripts.add(transcript);
    pending.addAll([
      for (final subagentId in transcript.subagentIds)
        (id: subagentId, parentId: id),
    ]);
  }

  return ConversationTree(
    transcripts: transcripts,
    warnings: [
      for (final transcript in transcripts) ...transcript.warnings,
      ...loadWarnings,
    ],
  );
}

Future<({TranscriptSource source, ConversationTranscript transcript})?>
_loadFromSources(String conversationId, List<TranscriptSource> sources) async {
  for (final source in sources) {
    if (await source.loadTranscript(conversationId) case final transcript?) {
      return (source: source, transcript: transcript);
    }
  }
  return null;
}
