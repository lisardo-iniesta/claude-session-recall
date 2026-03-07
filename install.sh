#!/usr/bin/env bash
# claude-session-recall installer
# Checks prerequisites, installs QMD, copies files, registers SessionEnd hook.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
PREFIX="${CLAUDE_SESSION_RECALL_PREFIX:-$HOME/.local}"
BIN_DIR="$PREFIX/bin"
LIB_DIR="$PREFIX/lib/claude-session-recall"
DATA_DIR="$PREFIX/share/claude-session-recall"
SETTINGS_FILE="$HOME/.claude/settings.json"

echo ""
echo "  claude-session-recall installer"
echo "  ================================"
echo ""

# --- 1. Check prerequisites ---
echo "Checking prerequisites..."

if ! command -v python3 &>/dev/null; then
    echo "ERROR: python3 is required but not found." >&2
    exit 1
fi

PY_VER=$(python3 -c 'import sys; print(sys.version_info.minor)')
if [ "$PY_VER" -lt 8 ]; then
    echo "ERROR: Python 3.8+ required (found 3.$PY_VER)" >&2
    exit 1
fi
echo "  Python 3.$PY_VER OK"

if ! command -v node &>/dev/null; then
    echo "ERROR: Node.js is required for QMD. Install from https://nodejs.org" >&2
    exit 1
fi
echo "  Node.js $(node --version) OK"

if [ ! -d "$HOME/.claude" ]; then
    echo "ERROR: ~/.claude not found. Is Claude Code installed?" >&2
    exit 1
fi
echo "  Claude Code directory found"

# --- 2. Ask where to save session markdown ---
DEFAULT_OUTPUT="$HOME/claude-sessions"
if [ -n "${CLAUDE_RECALL_OUTPUT_DIR:-}" ]; then
    OUTPUT_DIR="$CLAUDE_RECALL_OUTPUT_DIR"
    echo ""
    echo "Output directory (from env): $OUTPUT_DIR"
else
    echo ""
    echo "Where should session markdown files be saved?"
    echo "  This directory will contain searchable copies of your Claude Code sessions."
    echo ""
    read -r -p "  Output directory [$DEFAULT_OUTPUT]: " USER_OUTPUT
    OUTPUT_DIR="${USER_OUTPUT:-$DEFAULT_OUTPUT}"
fi

# Expand ~ if present
OUTPUT_DIR="${OUTPUT_DIR/#\~/$HOME}"
mkdir -p "$OUTPUT_DIR"
echo "  Output: $OUTPUT_DIR"

# --- 3. Install QMD if missing ---
echo ""
if command -v qmd &>/dev/null; then
    echo "QMD $(qmd --version 2>/dev/null || echo 'installed') OK"
else
    echo "Installing QMD (full-text search engine)..."
    npm install -g @tobilu/qmd
    echo "  QMD installed"
fi

# --- 4. Copy library files ---
echo ""
echo "Installing files..."
mkdir -p "$LIB_DIR" "$BIN_DIR" "$DATA_DIR"

cp "$REPO_DIR"/lib/parse-session.py "$LIB_DIR/"
cp "$REPO_DIR"/lib/export-session.sh "$LIB_DIR/"
cp "$REPO_DIR"/lib/backfill.sh "$LIB_DIR/"
cp "$REPO_DIR"/lib/recall.sh "$LIB_DIR/"
cp "$REPO_DIR"/lib/register-hook.py "$LIB_DIR/"
chmod +x "$LIB_DIR"/*.sh

# Save output dir preference
echo "$OUTPUT_DIR" > "$DATA_DIR/output-dir"

echo "  Library: $LIB_DIR"

# --- 5. Create bin stubs ---
# claude-session-recall (search)
cat > "$BIN_DIR/claude-session-recall" << EOF
#!/usr/bin/env bash
export CLAUDE_RECALL_OUTPUT_DIR="\${CLAUDE_RECALL_OUTPUT_DIR:-\$(cat "$DATA_DIR/output-dir" 2>/dev/null || echo "\$HOME/claude-sessions")}"
exec "$LIB_DIR/recall.sh" "\$@"
EOF
chmod +x "$BIN_DIR/claude-session-recall"

# claude-session-backfill
cat > "$BIN_DIR/claude-session-backfill" << EOF
#!/usr/bin/env bash
export CLAUDE_RECALL_OUTPUT_DIR="\${CLAUDE_RECALL_OUTPUT_DIR:-\$(cat "$DATA_DIR/output-dir" 2>/dev/null || echo "\$HOME/claude-sessions")}"
exec "$LIB_DIR/backfill.sh" "\$@"
EOF
chmod +x "$BIN_DIR/claude-session-backfill"

echo "  Commands: $BIN_DIR/claude-session-recall, claude-session-backfill"

# --- 6. Register SessionEnd hook ---
echo ""
echo "Registering SessionEnd hook..."

# The hook needs to know the output dir — create a wrapper that sets the env var
cat > "$LIB_DIR/hook-wrapper.sh" << EOF
#!/usr/bin/env bash
export CLAUDE_RECALL_OUTPUT_DIR="\$(cat "$DATA_DIR/output-dir" 2>/dev/null || echo "\$HOME/claude-sessions")"
export CLAUDE_RECALL_LOG="$DATA_DIR/export.log"
exec "$LIB_DIR/export-session.sh"
EOF
chmod +x "$LIB_DIR/hook-wrapper.sh"

python3 "$LIB_DIR/register-hook.py" register "$SETTINGS_FILE" "$LIB_DIR/hook-wrapper.sh"

# --- 7. Install /recall command for Claude Code ---
echo ""
echo "Installing Claude Code /recall command..."
COMMANDS_DIR="$HOME/.claude/commands"
mkdir -p "$COMMANDS_DIR"
cp "$REPO_DIR/commands/recall.md" "$COMMANDS_DIR/recall.md"
echo "  /recall command installed -> $COMMANDS_DIR/recall.md"

# --- 7b. Install /recall-sessions skill for Claude Code ---
echo "Installing Claude Code /recall-sessions skill..."
SKILLS_DIR="$HOME/.claude/skills/recall-sessions"
mkdir -p "$SKILLS_DIR"
cp "$REPO_DIR/skills/recall-sessions/SKILL.md" "$SKILLS_DIR/SKILL.md"
echo "  /recall-sessions skill installed -> $SKILLS_DIR/SKILL.md"

# --- 8. Initialize QMD index ---
if command -v qmd &>/dev/null; then
    if ! qmd --index sessions collection list &>/dev/null 2>&1; then
        echo ""
        echo "Initializing search index..."
        qmd --index sessions collection add "$OUTPUT_DIR" --name sessions --mask "**/*.md" 2>/dev/null || true
        qmd --index sessions context add / "Claude Code session transcripts: decisions, debugging context, project discussions, implementation details" 2>/dev/null || true
        echo "  QMD sessions index created"
    else
        echo "  QMD sessions index already exists"
    fi
fi

# --- Done ---
echo ""
echo "  Installed successfully!"
echo ""
echo "  Hook:      SessionEnd -> $LIB_DIR/hook-wrapper.sh"
echo "  /recall:          Use /recall <query> inside Claude Code sessions"
echo "  /recall-sessions: Skill-based search (richer context for Claude)"
echo "  CLI:       claude-session-recall \"query\" (standalone search)"
echo "  Backfill:  claude-session-backfill"
echo "  Output:    $OUTPUT_DIR"
echo ""

# Check if BIN_DIR is in PATH
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    echo "  WARNING: $BIN_DIR is not in your PATH."
    echo "  Add to your shell profile:"
    echo ""
    echo "    export PATH=\"$BIN_DIR:\$PATH\""
    echo ""
fi

echo "  Next: run 'claude-session-backfill' to index existing sessions."
echo ""
