---
name: closing-obsolete-issues
description: Find and close obsolete, stale, or not reproducible issues in the dart-lang/ai repository.
---

# Closing Obsolete Issues

Use this skill to find old, outdated issues in the `dart-lang/ai` repository that can be closed because they have been fixed, are stale, obsolete, or not reproducible.

## Instructions

1. **Identify Target Issues**:
   - Use the GitHub CLI (`gh`) to search for the oldest open issues.
   - Use any label that the user gives you, or none if the user does not specify any issue labels.
   - Sort by creation date (`created-asc`) or last update (`updated-asc`) to find the most likely candidates for being outdated.
   - Fetch at least 10-20 candidates.
   - Example command (with label): `gh issue list --repo dart-lang/ai --search "label:bug is:open sort:created-asc" --limit 20 | cat`
   - Example command (without label): `gh issue list --repo dart-lang/ai --search "is:open sort:created-asc" --limit 20 | cat`

2. **Investigate Status**:
   - For each candidate, analyze its description and comments.
   - Use `gh issue view <number> --repo dart-lang/ai` to get details.
   - Compare the issue's request or reported bug with the current state of the codebase.
   - Refer to `references/rationale_templates.md` for a library of common reasons issues become outdated.
   - **Safety Rule**: Do not assume a bug is fixed or obsolete just because the code has been updated. Verify if the specific bug behavior is still possible. Valid bugs or feature requests should not be closed as stale just because they are old or have no activity. Inactivity alone does not invalidate a feature request or bug report.

3. **Draft and Review Closing Comments (CRITICAL MANDATE)**:
   - For issues identified as candidates for closing, draft a detailed comment for each explaining *why* it can be closed.
   - **Style Constraint**: DO NOT use em dashes (—) in the comments. Use hyphens (-) or colons (:) instead.
   - **Template**: Consult `references/rationale_templates.md` for wording inspiration.
   - Each comment MUST end with: "If there is more work to do here, please let us know by commenting on this issue or filing a new one with up to date information. Thanks!"
   - **User Approval Required**: You MUST present the identified issues (including URLs to the issues for easy navigation) and their drafted comments to the user and obtain explicit approval BEFORE running any command that closes an issue.

4. **Iterate on Skill Knowledge (Learning Loop)**:
   - If you discover a new, distinct category of closing rationale that is not covered in `references/rationale_templates.md`, **update the reference file** to include it.

5. **Execute and Summarize**:
   - Once approved, use `gh issue close` with the `-c` flag to post the comment and close the issue.
   - Provide the user with a clean bulleted list of links to each closing comment.

## Tips

- Use available file and content search tools (such as `grep`, `ripgrep`) to check the current codebase for references to the issue or relevant code.
- Look for related PRs that might have fixed the issue but didn't close it automatically.
