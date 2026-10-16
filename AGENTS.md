# Commit workflow

- Automatically create a local Git commit after completing a coherent change and passing the relevant checks. No additional confirmation is needed.
- Review the diff and stage only files belonging to the completed work. Preserve unrelated user changes, and never commit credentials, secrets, or temporary browser/session data.
- Use a concise commit message describing the resulting behavior, and report the commit hash and validation in the final response.
- If checks fail or a commit is blocked, explain the issue rather than claiming completion.
- Push commits only when the user requests it.
