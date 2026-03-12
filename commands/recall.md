# /recall — Search Claude Code Session History

Search your past Claude Code sessions using QMD full-text search.

## Instructions

The user wants to search their Claude Code session history. Their query is: $ARGUMENTS

1. Run `qmd --index sessions search "$ARGUMENTS"` using the Bash tool
2. Parse the results — each result shows:
   - File path (contains session date and UUID)
   - Score (higher = more relevant)
   - Matching text snippet
3. Present the **top 3-5 results** clearly:
   - Session date and project (from the file path: `YYYY/MM-DD/uuid.md`)
   - Relevance score
   - The matching snippet with context
4. If the user wants more detail on a specific result, read the full markdown file from the path shown (replace `qmd://sessions/` prefix with the output directory, default `~/claude-sessions/`)

## Deep Search (QMD 2.0+)

If fast search doesn't find what the user needs, escalate to hybrid search (~13s):

```bash
qmd --index sessions query "authentication refactoring"
qmd --index sessions query --intent "the recall skill, not auth" "recall"
```

## Examples

```bash
# Basic search
qmd --index sessions search "authentication refactoring"

# More results
qmd --index sessions search --limit 10 "docker deployment"
```

## If no results

- The QMD index may need updating: `qmd --index sessions update && qmd --index sessions embed`
- The user may not have run `claude-session-backfill` yet
- Try broader search terms
- Try `qmd --index sessions query` for hybrid search
