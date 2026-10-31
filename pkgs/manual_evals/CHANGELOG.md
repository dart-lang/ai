## 0.1.0-wip

- Initial experimental structure for `manual_evals`.
- Add APIs for loading agent conversation transcripts and their subagents'
  transcripts: `loadTranscript`, `loadConversationTree`,
  `resolveConversationId`, `pairToolResults`, and the `TranscriptSource`
  extension point, implemented by `AntigravityTranscriptSource`.
- Report signs of unrecognized transcript formats as `TranscriptWarning`s, and
  add `checkTranscriptFormat` and `tool/check_transcript_format.dart` to check
  real transcripts for them.
