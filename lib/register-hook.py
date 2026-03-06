#!/usr/bin/env python3
"""Register/unregister the SessionEnd hook in Claude Code settings."""

import json
import shutil
import sys
from pathlib import Path

HOOK_MARKER = "export-session.sh"  # Used to detect our hook


def register(settings_path: str, hook_command: str):
    """Add SessionEnd hook to settings.json, merging with existing config."""
    settings = Path(settings_path)

    if settings.exists():
        shutil.copy2(settings, settings.with_suffix(".json.bak"))
        config = json.loads(settings.read_text())
    else:
        settings.parent.mkdir(parents=True, exist_ok=True)
        config = {}

    hooks = config.setdefault("hooks", {})
    session_end = hooks.setdefault("SessionEnd", [])

    # Idempotent — check if already registered
    for entry in session_end:
        for hook in entry.get("hooks", []):
            if HOOK_MARKER in hook.get("command", ""):
                print("Hook already registered.")
                return

    session_end.append({
        "hooks": [{
            "type": "command",
            "command": hook_command,
            "timeout": 30
        }]
    })

    settings.write_text(json.dumps(config, indent=2) + "\n")
    print(f"Registered SessionEnd hook: {hook_command}")


def unregister(settings_path: str):
    """Remove our SessionEnd hook from settings.json, preserving everything else."""
    settings = Path(settings_path)
    if not settings.exists():
        return

    config = json.loads(settings.read_text())
    session_end = config.get("hooks", {}).get("SessionEnd", [])

    config["hooks"]["SessionEnd"] = [
        entry for entry in session_end
        if not any(HOOK_MARKER in h.get("command", "") for h in entry.get("hooks", []))
    ]

    # Clean up empty SessionEnd array
    if not config["hooks"]["SessionEnd"]:
        del config["hooks"]["SessionEnd"]
    if not config.get("hooks"):
        del config["hooks"]

    settings.write_text(json.dumps(config, indent=2) + "\n")
    print("Hook unregistered.")


def main():
    if len(sys.argv) < 3:
        print("Usage: register-hook.py <register|unregister> <settings_path> [hook_command]", file=sys.stderr)
        sys.exit(1)

    action = sys.argv[1]
    settings_path = sys.argv[2]

    if action == "register":
        if len(sys.argv) < 4:
            print("Error: hook_command required for register", file=sys.stderr)
            sys.exit(1)
        register(settings_path, sys.argv[3])
    elif action == "unregister":
        unregister(settings_path)
    else:
        print(f"Unknown action: {action}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
