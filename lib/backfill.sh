#!/usr/bin/env bash
# Backfill all existing Claude Code sessions into searchable markdown.
# Run once after install, then the SessionEnd hook handles new sessions.

set -euo pipefail

LIB_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="${CLAUDE_RECALL_OUTPUT_DIR:-$HOME/claude-sessions}"
PARSER="$LIB_DIR/parse-session.py"
LOGFILE="${CLAUDE_RECALL_LOG:-$HOME/.local/share/claude-session-recall/backfill.log}"

mkdir -p "$(dirname "$LOGFILE")" "$OUTPUT_DIR"

TOTAL=0
EXPORTED=0
SKIPPED=0

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOGFILE"; }

# Parse arguments
DRY_RUN=false
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        --help|-h)
            echo "Usage: claude-session-backfill [--dry-run]"
            echo ""
            echo "Export all existing Claude Code sessions to searchable markdown."
            echo ""
            echo "Options:"
            echo "  --dry-run   Show what would be exported without writing files"
            echo ""
            echo "Environment:"
            echo "  CLAUDE_RECALL_OUTPUT_DIR  Output directory (default: ~/claude-sessions)"
            echo "  CLAUDE_RECALL_MIN_WORDS   Min words to export a session (default: 200)"
            exit 0
            ;;
    esac
done

log "Starting backfill to $OUTPUT_DIR..."
if $DRY_RUN; then
    log "(dry run — no files will be written)"
fi

while IFS= read -r jsonl; do
    TOTAL=$((TOTAL + 1))
    if $DRY_RUN; then
        # Just check if it would be exported
        RESULT=$(python3 "$PARSER" "$jsonl" "/tmp/claude-recall-dryrun-$$" 2>/dev/null) || true
        rm -rf "/tmp/claude-recall-dryrun-$$"
    else
        RESULT=$(python3 "$PARSER" "$jsonl" "$OUTPUT_DIR" 2>/dev/null) || true
    fi
    if [ -n "$RESULT" ] && { $DRY_RUN || [ -f "$RESULT" ]; }; then
        EXPORTED=$((EXPORTED + 1))
    else
        SKIPPED=$((SKIPPED + 1))
    fi
    # Progress every 50 files
    if [ $((TOTAL % 50)) -eq 0 ]; then
        log "Progress: $TOTAL processed, $EXPORTED exported, $SKIPPED skipped"
    fi
done < <(find "$HOME/.claude/projects" -name "*.jsonl" -type f 2>/dev/null)

log "Backfill complete: $TOTAL total, $EXPORTED exported, $SKIPPED skipped"

# Update QMD sessions index
if ! $DRY_RUN && command -v qmd &>/dev/null; then
    log "Updating QMD sessions index..."
    qmd --index sessions update 2>&1 | tail -3
    log "Embedding sessions index..."
    qmd --index sessions embed 2>&1 | tail -3
    log "QMD sessions index ready"
elif ! command -v qmd &>/dev/null; then
    log "WARN: qmd not found. Install with: npm install -g @tobilu/qmd"
    log "Markdown files were exported but not indexed for search."
fi

log "Done!"
