---
name: manual-evals-trajectory
description: Summarizes what an agent conversation and its subagents did, turn by turn, with the tools called, which calls failed and why, how long each turn took, and the files modified. Use to review an agent's tool use or to compare trajectories, for example in A/B evaluations.
---

# Trajectory

1. Run the script from this skill's directory. Without a conversation ID, it
   reports on the current conversation:
   ```bash
   dart run scripts/trajectory.dart [conversation-id]
   ```
2. Show the user the Markdown report it prints. In it, ✅ marks a tool call
   that succeeded, ❌ one that failed, and ⏳ one that hadn't finished.

Note: The report lists only the slash commands and skills that the user
explicitly triggered. Transcripts don't record skills that the agent picked up
on its own.
