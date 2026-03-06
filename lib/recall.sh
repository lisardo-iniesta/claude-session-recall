#!/usr/bin/env bash
# Search Claude Code session transcripts via QMD.

set -euo pipefail

if [ $# -eq 0 ] || [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Usage: claude-session-recall <query> [options]"
    echo ""
    echo "Search your Claude Code session history."
    echo ""
    echo "Options:"
    echo "  -n NUM    Number of results (default: 5)"
    echo "  --json    JSON output for scripting"
    echo "  --help    Show this help"
    echo ""
    echo "Examples:"
    echo "  claude-session-recall \"authentication flow\""
    echo "  claude-session-recall -n 10 \"docker deployment\""
    echo "  claude-session-recall --json \"refactoring\""
    echo ""
    echo "Environment:"
    echo "  CLAUDE_RECALL_OUTPUT_DIR  Session markdown directory (default: ~/claude-sessions)"
    exit 0
fi

if ! command -v qmd &>/dev/null; then
    echo "Error: qmd not found." >&2
    echo "Install with: npm install -g @tobilu/qmd" >&2
    echo "Then run: claude-session-backfill" >&2
    exit 1
fi

exec qmd --index sessions search "$@"
