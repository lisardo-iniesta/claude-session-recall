# Contributing

## Project Structure

```
lib/
  parse-session.py      # JSONL → Markdown converter (Python stdlib only)
  export-session.sh     # SessionEnd hook entry point
  backfill.sh           # Batch export existing sessions
  recall.sh             # CLI search wrapper around QMD
  register-hook.py      # Safe settings.json hook registration
commands/recall.md      # Claude Code /recall custom command
skills/recall-sessions/ # Claude Code /recall-sessions skill
install.sh              # Interactive installer
uninstall.sh            # Clean removal
tests/                  # Bash test suite
```

## Development

**Run tests:**

```bash
bash tests/test-parse-session.sh
```

**Key constraints:**
- Python code must stay **stdlib only** — no pip dependencies
- Python **3.8+ compatibility** required (no walrus operator, no `match/case`, no `type` statements)
- Shell scripts use `bash` with `set -euo pipefail`

## Submitting Changes

1. Fork the repo and create a feature branch
2. Run `bash tests/test-parse-session.sh` — all tests must pass
3. Open a pull request with a clear description of what and why
