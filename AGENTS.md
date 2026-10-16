# Commit workflow

- Automatically create a local Git commit after completing a coherent change and passing the relevant checks. No additional confirmation is needed.
- Review the diff and stage only files belonging to the completed work. Preserve unrelated user changes, and never commit credentials, secrets, or temporary browser/session data.
- For commit messages, load the latest `git-commit-writer` skill through the Agensi MCP (`https://agensi.io/skills/git-commit-writer`) and apply it to the staged diff. If Agensi is unavailable, use Angular-style Conventional Commits (`type(scope): description`). The user's automatic-commit authorization above takes precedence over a skill's confirmation step.
- Report the commit hash and validation in the final response.
- If checks fail or a commit is blocked, explain the issue rather than claiming completion.
- Push commits only when the user requests it.
