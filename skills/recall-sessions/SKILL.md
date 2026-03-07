---
name: recall-sessions
description: Search Claude Code session transcripts using QMD hybrid search. Use when the user asks to recall a previous conversation, find what was discussed, search session history, or look up past Claude Code interactions. Commands: /recall-sessions
---

# /recall-sessions — Session History Search

Search Claude Code session transcripts using QMD's hybrid BM25 + semantic search.

## Usage

```
/recall-sessions <query>
```

## How It Works

1. Run `qmd --index sessions search "<query>"` with the user's query
2. Parse the results — each result shows session file path, score, and matching text chunk
3. Present the top results with context (session date, project, branch from frontmatter)
4. If the user wants the full session, read the markdown file from the path

## Session Metadata

Each session markdown has YAML frontmatter with:
- `session_id` — UUID of the Claude Code session
- `date` — when the session occurred
- `project` — extracted from CWD
- `branch` — git branch during the session
- `model` — Claude model used
- `messages` — number of user messages

## Examples

```bash
# Search all sessions
qmd --index sessions search "authentication system refactoring"

# Search with more results
qmd --index sessions search --limit 10 "docker deployment"

# Search for sessions about a specific project
qmd --index sessions search "my-project memory search"
```

## Troubleshooting

- **No results**: Run `qmd --index sessions update && qmd --index sessions embed` to refresh
- **Empty index**: Sessions only appear after SessionEnd hook fires — run `claude-session-backfill` for historical sessions
- **`qmd` not found**: Install with `npm i -g @tobilu/qmd`

## Index Info

- **Index**: `sessions` (`~/.cache/qmd/sessions.sqlite`)
- **Source**: `~/claude-sessions/` (auto-populated by SessionEnd hook, configurable via `CLAUDE_RECALL_OUTPUT_DIR`)
- **Collections**: `sessions` — exported session markdown files
- **Auto-update**: SessionEnd hook exports JSONL → markdown → QMD on every session end
