#!/usr/bin/env python3
"""Parse Claude Code session JSONL into clean markdown for indexing."""

import json
import subprocess
import sys
import os
from pathlib import Path
from datetime import datetime

MIN_WORDS = int(os.environ.get("CLAUDE_RECALL_MIN_WORDS", "200"))


def extract_project_name(cwd: str) -> str:
    """Extract project name from CWD. Uses git toplevel or directory name."""
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, cwd=cwd, timeout=5
        )
        if result.returncode == 0:
            return Path(result.stdout.strip()).name
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        pass
    return Path(cwd).name


def parse_session(jsonl_path: str, output_dir: str):
    """Parse JSONL session file into markdown. Returns output path or None if skipped."""
    lines = Path(jsonl_path).read_text().splitlines()

    session_id = None
    cwd = None
    branch = None
    model = None
    messages = []
    user_count = 0
    latest_timestamp = None

    for line in lines:
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            continue

        entry_type = entry.get("type")

        # Extract metadata from first entries
        if session_id is None:
            session_id = entry.get("sessionId")
        if cwd is None:
            cwd = entry.get("cwd")
        if branch is None:
            branch = entry.get("gitBranch")

        # Track latest timestamp explicitly
        ts = entry.get("timestamp")
        if ts:
            latest_timestamp = ts

        if entry_type == "user":
            msg = entry.get("message", {})
            content = msg.get("content", "")
            if isinstance(content, str) and content.strip():
                # Skip system-reminder-only messages and meta messages
                if entry.get("isMeta"):
                    continue
                messages.append(("User", content.strip()))
                user_count += 1

        elif entry_type == "assistant":
            msg = entry.get("message", {})
            if model is None:
                model = msg.get("model")
            content = msg.get("content", [])
            if isinstance(content, list):
                text_parts = []
                for block in content:
                    if isinstance(block, dict) and block.get("type") == "text":
                        text = block.get("text", "").strip()
                        if text:
                            text_parts.append(text)
                if text_parts:
                    messages.append(("Assistant", "\n\n".join(text_parts)))

    # Skip trivial sessions
    total_text = " ".join(text for _, text in messages)
    word_count = len(total_text.split())
    if word_count < MIN_WORDS:
        return None

    # Build markdown
    project = extract_project_name(cwd or "unknown")
    try:
        date = datetime.fromisoformat(latest_timestamp.replace("Z", "+00:00")).strftime("%Y-%m-%d")
    except (ValueError, AttributeError, TypeError):
        date = datetime.now().strftime("%Y-%m-%d")

    md_lines = [
        "---",
        f"session_id: {session_id or 'unknown'}",
        f"date: {date}",
        f"project: {project}",
        f"branch: {branch or 'unknown'}",
        f"model: {model or 'unknown'}",
        f"cwd: {cwd or 'unknown'}",
        f"messages: {user_count}",
        "tags: [claude-session]",
        "---",
        "",
        f"# Session: {project} — {date}",
        "",
    ]

    for role, text in messages:
        md_lines.append(f"## {role}")
        md_lines.append(text)
        md_lines.append("")

    # Write to output
    date_parts = date.split("-")
    out_subdir = Path(output_dir) / date_parts[0] / f"{date_parts[1]}-{date_parts[2]}"
    out_subdir.mkdir(parents=True, exist_ok=True)

    out_file = out_subdir / f"{session_id or 'unknown'}.md"
    out_file.write_text("\n".join(md_lines))
    return str(out_file)


def main():
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <jsonl_path> <output_dir>", file=sys.stderr)
        sys.exit(1)

    jsonl_path = sys.argv[1]
    output_dir = sys.argv[2]

    if not Path(jsonl_path).exists():
        print(f"Error: {jsonl_path} not found", file=sys.stderr)
        sys.exit(1)

    result = parse_session(jsonl_path, output_dir)
    if result:
        print(result)
    else:
        print("SKIPPED", file=sys.stderr)
        sys.exit(0)


if __name__ == "__main__":
    main()
