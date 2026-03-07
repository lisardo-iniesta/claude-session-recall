#!/usr/bin/env bash
# claude-session-recall uninstaller
# Removes installed files and hook. Does NOT delete exported sessions or QMD index.

set -euo pipefail

PREFIX="${CLAUDE_SESSION_RECALL_PREFIX:-$HOME/.local}"
BIN_DIR="$PREFIX/bin"
LIB_DIR="$PREFIX/lib/claude-session-recall"
DATA_DIR="$PREFIX/share/claude-session-recall"
SETTINGS_FILE="$HOME/.claude/settings.json"

echo ""
echo "  claude-session-recall uninstaller"
echo "  =================================="
echo ""

# Unregister hook
if [ -f "$LIB_DIR/register-hook.py" ]; then
    echo "Removing SessionEnd hook..."
    python3 "$LIB_DIR/register-hook.py" unregister "$SETTINGS_FILE"
fi

# Remove library files
if [ -d "$LIB_DIR" ]; then
    echo "Removing library files..."
    rm -rf "$LIB_DIR"
fi

# Remove data files
if [ -d "$DATA_DIR" ]; then
    echo "Removing data files..."
    rm -rf "$DATA_DIR"
fi

# Remove bin stubs
for cmd in claude-session-recall claude-session-backfill; do
    if [ -f "$BIN_DIR/$cmd" ]; then
        rm -f "$BIN_DIR/$cmd"
    fi
done
echo "Removing CLI commands..."

# Remove Claude Code /recall command
RECALL_CMD="$HOME/.claude/commands/recall.md"
if [ -f "$RECALL_CMD" ]; then
    echo "Removing /recall command..."
    rm -f "$RECALL_CMD"
fi

# Remove Claude Code /recall-sessions skill
SKILL_DIR="$HOME/.claude/skills/recall-sessions"
if [ -d "$SKILL_DIR" ]; then
    echo "Removing /recall-sessions skill..."
    rm -rf "$SKILL_DIR"
fi

echo ""
echo "  Uninstalled successfully!"
echo ""
echo "  Preserved (remove manually if desired):"
echo "    Sessions:  ~/claude-sessions/"
echo "    QMD index: ~/.cache/qmd/sessions.sqlite"
echo ""
