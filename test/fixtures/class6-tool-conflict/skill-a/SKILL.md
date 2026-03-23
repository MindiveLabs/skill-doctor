---
name: read-only-assistant
version: 1.0.0
description: |
  Read-only analysis assistant. Answers questions about code without making changes.
  Use when asked to "analyze without changing" or "read-only mode".
disable-model-invocation: true
allowed-tools:
  - Read
  - Grep
  - Glob
---

# read-only-assistant

Analysis only — no file modifications.
