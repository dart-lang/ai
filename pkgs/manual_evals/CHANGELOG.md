## 0.1.0-wip

- Initial experimental structure for `manual_evals`.
- Require Dart `^3.13.0`.
- Add APIs for loading agent conversation transcripts and their subagents'
  transcripts: `loadTranscript`, `loadConversationTree`,
  `resolveConversationId`, `pairToolResults`, and the `TranscriptSource`
  extension point, implemented by `AntigravityTranscriptSource`.
- Report signs of unrecognized transcript formats as `TranscriptWarning`s, and
  add `checkTranscriptFormat` and `tool/check_transcript_format.dart` to check
  real transcripts for them.
- Add the `manual-evals-token-usage` skill, which reports the recorded token
  usage of a conversation and its subagents, and the `measureTokenUsage`,
  `formatTokenReport`, and `loadConversationTreeFromArgs` APIs behind it.
