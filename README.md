# skill-doctor

A standalone [Claude Code](https://claude.ai/claude-code) meta-skill that detects and resolves conflicts between installed skills.

When you have multiple skills installed, some may shadow each other, collide on triggers, or race to make proactive suggestions. skill-doctor scans your skill inventory and tells you exactly what's wrong — then helps you fix it.

---

## Conflict Classes

| Class | Severity | Name | Description |
|-------|----------|------|-------------|
| 1 | CRITICAL | Name Shadow | Two skills share the same `name:` — one is silently hidden |
| 2 | HIGH | Trigger Collision | Overlapping "Use when asked to" phrases — Claude picks one arbitrarily |
| 3 | HIGH | Semantic Overlap | Same user intent, different descriptions — both skills compete |
| 4 | MEDIUM | Proactive Race | Both skills have "Proactively suggest when" clauses that fire together |
| 5 | MEDIUM | State File Collision | Two skills read/write the same state file |
| 6 | LOW | Tool Conflict | Redundant `disable-model-invocation: true` across multiple skills |
| 7 | LOW | Subsumption | One skill fully covers everything the other does |

Classes 1, 5, and 6 are detected statically (shell script, no LLM required). Classes 2, 3, 4, and 7 are detected semantically by the LLM during a `/skill-doctor` run.

---

## Installation

```bash
git clone git@github.com:MindiveLabs/skill-doctor.git
cd skill-doctor
./setup
```

This copies skill-doctor to `~/.claude/skills/skill-doctor/`. Hook registration happens automatically on first run.

**Requirements:** bash 3.2+ (macOS default), python3

---

## Usage

```
/skill-doctor           — scan and report conflicts
/skill-doctor --fix     — scan and interactively resolve each conflict
```

On first run, skill-doctor registers two background hooks:
- **PostToolUse (Write/Edit)** — scans after any `SKILL.md` file is edited
- **UserPromptSubmit** — scans at the start of each session (skips if nothing changed)

Both hooks print an advisory message if CRITICAL or HIGH conflicts are found. They never block.

---

## How It Works

```
/skill-doctor
    │
    ├── Phase 1: Discovery
    │     Enumerate all SKILL.md files across personal (~/.claude/skills/),
    │     project (.claude/skills/), and settings.json additionalDirectories
    │
    ├── Phase 2: Static Analysis
    │     skill-doctor-scan --scope all
    │     Detects: Class 1 (Name Shadow), Class 5 (State Collision), Class 6 (Tool Conflict)
    │     Output: JSON to stdout; exit 1 if CRITICAL found
    │
    ├── Phase 3: Semantic Analysis (LLM)
    │     Reads metadata cache (~/.config/skill-doctor/metadata-cache.json)
    │     Generates 1-line summaries for new/changed skills
    │     Detects: Class 2 (Trigger), Class 3 (Overlap), Class 4 (Proactive), Class 7 (Subsumption)
    │
    ├── Phase 4: Report
    │     Merges static + semantic results
    │     Filters known-conflicts.json suppressions
    │     Prints ASCII conflict map by severity
    │
    ├── Phase 5: Interactive Resolution (--fix only)
    │     Per-conflict: keep A, keep B, mark intentional, edit content, or skip
    │     Removed skills moved to ~/.config/skill-doctor/trash/ (recoverable)
    │
    └── Phase 6: Hook Registration (first run, idempotent)
          Writes PostToolUse + UserPromptSubmit hooks to ~/.claude/settings.json
```

---

## State Files

All runtime state lives in `~/.config/skill-doctor/`:

```
~/.config/skill-doctor/
├── metadata-cache.json    # Skill summaries keyed by path + mtime
├── known-conflicts.json   # User-acknowledged conflict suppressions
├── removals.jsonl         # Log of skills moved to trash
├── hook.lock              # Debounce lockfile (30s window)
└── trash/                 # Removed skill directories (recoverable)
```

---

## Static Scanner

`bin/skill-doctor-scan` can be used standalone:

```bash
# Scan all scopes
skill-doctor-scan --scope all

# Scan only personal skills (~/.claude/skills/)
skill-doctor-scan --scope global

# Scan only project skills (.claude/skills/)
skill-doctor-scan --scope local

# Scan a specific directory (useful for testing)
skill-doctor-scan --skills-dir /path/to/skills/
```

**Output:** JSON to stdout
```json
{
  "schema_version": 1,
  "skills": [{"name": "...", "path": "...", "scope": "...", "tools": [...]}],
  "conflicts": [{"class": 1, "severity": "CRITICAL", "skill_a": "...", "skill_b": "...", "path_a": "...", "path_b": "...", "reason": "..."}],
  "warnings": [{"path": "...", "reason": "..."}]
}
```

**Exit codes:** `0` = no CRITICAL conflicts; `1` = CRITICAL conflicts found

---

## Tests

```bash
cd test
./static.test.sh    # 23 tests for the static scanner
./hook.test.sh      # 12 tests for the hook (debounce, exit codes, advisory output)
```

All 35 tests pass on bash 3.2+ (macOS default).

---

## Upgrading

```bash
cd skill-doctor
git pull
./setup
```

skill-doctor checks for updates on each run via `bin/skill-doctor-update-check` (GitHub Releases API, silent on failure).

---

## License

MIT
