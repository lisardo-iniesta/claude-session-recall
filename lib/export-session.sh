#!/usr/bin/env bash
# Export Claude Code session JSONL to markdown for indexing.
# Called by SessionEnd hook — reads hook input from stdin.

set -euo pipefail

LIB_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="${CLAUDE_RECALL_OUTPUT_DIR:-$HOME/claude-sessions}"
LOGFILE="${CLAUDE_RECALL_LOG:-$HOME/.local/share/claude-session-recall/export.log}"

mkdir -p "$(dirname "$LOGFILE")"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOGFILE"; }

# Read hook input from stdin
INPUT=$(cat)

# Extract transcript_path and session_id from stdin JSON
TRANSCRIPT_PATH=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('transcript_path',''))" 2>/dev/null || echo "")
SESSION_ID=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('session_id',''))" 2>/dev/null || echo "")

log "Raw input: transcript_path=$TRANSCRIPT_PATH session_id=$SESSION_ID"

# If transcript_path doesn't end in .jsonl, find the JSONL by session_id
if [ -n "$TRANSCRIPT_PATH" ] && [[ "$TRANSCRIPT_PATH" != *.jsonl ]]; then
    log "WARN: transcript_path is not JSONL ($TRANSCRIPT_PATH), falling back to session_id scan"
    TRANSCRIPT_PATH=""
fi

# Fallback: if transcript_path is empty or missing, find JSONL by session_id
if { [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; } && [ -n "$SESSION_ID" ]; then
    log "Scanning for JSONL by session_id: $SESSION_ID"
    TRANSCRIPT_PATH=$(find "$HOME/.claude/projects" -name "${SESSION_ID}.jsonl" -type f 2>/dev/null | head -1)
fi

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
    log "ERROR: No transcript found. session_id=$SESSION_ID transcript_path=$TRANSCRIPT_PATH"
    exit 0  # Don't fail the hook
fi

log "Exporting session: $SESSION_ID from $TRANSCRIPT_PATH"

# Parse JSONL to markdown
RESULT=$(python3 "$LIB_DIR/parse-session.py" "$TRANSCRIPT_PATH" "$OUTPUT_DIR" 2>/dev/null)

if [ -z "$RESULT" ]; then
    log "SKIPPED: Session too short (<${CLAUDE_RECALL_MIN_WORDS:-200} words)"
    exit 0
fi

log "Exported to: $RESULT"

# Update QMD sessions index
if command -v qmd &>/dev/null; then
    qmd --index sessions update 2>/dev/null && qmd --index sessions embed 2>/dev/null
    log "QMD sessions index updated"
else
    log "WARN: qmd not found, skipping index update"
fi

log "Done"
