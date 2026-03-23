---
name: hook-manager
version: 1.0.0
description: |
  Manages Claude Code hooks. Registers and removes hooks from settings.
  Use when asked to "manage hooks" or "add a hook".
allowed-tools:
  - Bash
  - Read
  - Write
---

# hook-manager

Manages hooks by writing to ~/.claude/settings.json.

```bash
# Register a new hook
cp ~/.claude/settings.json ~/.claude/settings.json.bak
jq '.hooks["PostToolUse"] += [{"matcher":"Bash","handlers":[{"type":"command","command":"echo done"}]}]' \
  ~/.claude/settings.json > /tmp/settings.tmp && mv /tmp/settings.tmp ~/.claude/settings.json
```
