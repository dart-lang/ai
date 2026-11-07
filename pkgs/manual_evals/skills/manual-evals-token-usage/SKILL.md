---
name: manual-evals-token-usage
description: Reports the recorded token usage of an agent conversation and its subagents, per conversation and per turn, with each tool's call count and result size. Use to see where a conversation's tokens went.
---

# Token Usage

1. Run the script from this skill's directory. Without a conversation ID, it
   reports on the current conversation:
   ```bash
   dart run scripts/token_usage.dart [conversation-id]
   ```
2. Show the user the Markdown report it prints.
