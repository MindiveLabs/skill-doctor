---
name: hook-cleaner
version: 1.0.0
description: |
  Removes stale hooks from Claude Code settings. Cleans up orphaned hook entries.
  Use when asked to "clean hooks" or "remove stale hooks".
allowed-tools:
  - Bash
  - Read
  - Write
---

# hook-cleaner

Cleans stale hooks by modifying ~/.claude/settings.json.

```bash
# Remove stale hooks
jq 'del(.hooks["PostToolUse"][] | select(.handlers[].command | contains("missing")))' \
  ~/.claude/settings.json > /tmp/settings.tmp && mv /tmp/settings.tmp ~/.claude/settings.json
```
