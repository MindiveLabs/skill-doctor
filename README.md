# skill-doctor

A standalone [Claude Code](https://claude.ai/claude-code) meta-skill that detects and resolves conflicts between installed skills.

When you have multiple skills installed, some may shadow each other, collide on triggers, or race to make proactive suggestions. skill-doctor scans your skill inventory and tells you exactly what's wrong — then helps you fix it.

**Read-only by default.** skill-doctor never modifies skill files. The only action it takes (with your explicit confirmation) is moving a skill to trash — which is always recoverable.

---

## Conflict Types

| Type | Severity | Description |
|------|----------|-------------|
| Name Shadow | Critical | Two skills share the same name — one is silently hidden |
| Trigger Collision | High | Overlapping "Use when asked to" phrases — Claude picks one arbitrarily |
| Semantic Overlap | High | Same user intent, different descriptions — both skills compete |
| Proactive Race | Medium | Both skills have "Proactively suggest when" clauses that fire together |
| State File Collision | Medium | Two skills read/write the same state file |
| Tool Conflict | Low | Redundant `disable-model-invocation: true` across multiple skills |
| Subsumption | Low | One skill fully covers everything the other does |

Name Shadow, State File Collision, and Tool Conflict are detected statically (shell script, no LLM required). The remaining four types are detected semantically by the LLM during a `/skill-doctor` run.

---

## Installation

```bash
git clone git@github.com:MindiveLabs/skill-doctor.git ~/.claude/skills/skill-doctor && cd ~/.claude/skills/skill-doctor && ./setup
```

**Requirements:** bash 3.2+ (macOS default), python3

Hook registration (background scanning on skill changes) happens automatically on the first `/skill-doctor` run.

---

## Usage

```
/skill-doctor           — scan and report conflicts
/skill-doctor --fix     — scan and interactively resolve each conflict
```

On first run, skill-doctor registers two background hooks:
- **PostToolUse (Write/Edit)** — scans after any `SKILL.md` file is edited
- **UserPromptSubmit** — scans at the start of each session (skips if nothing changed)

Both hooks print an advisory message if critical or high-severity conflicts are found. They never block.

Each scan saves a full markdown report to `~/.skill-doctor/reports/` and prints the path.

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
    │     Detects: Name Shadow, State File Collision, Tool Conflict
    │     Output: JSON to stdout; exit 1 if critical conflicts found
    │
    ├── Phase 3: Metadata Cache + Semantic Analysis
    │     Reads ~/.skill-doctor/metadata-cache.json
    │     Per-skill: mtime check (fast) → SHA-256 checksum (on mtime miss)
    │     Regenerates only when checksum differs (content truly changed)
    │     Each entry: rich summary (max 300 chars), trigger phrases,
    │     proactive clauses, tools list, mtime, checksum
    │     Detects: Trigger Collision, Semantic Overlap, Proactive Race, Subsumption
    │
    ├── Phase 4: Report
    │     Merges static + semantic results
    │     Filters known-conflicts.json suppressions
    │     Prints conflict map by severity (human-readable names)
    │     Saves full report to ~/.skill-doctor/reports/ and prints the path
    │
    ├── Phase 5: Interactive Resolution (--fix only)
    │     Per-conflict: keep A, keep B, mark intentional, edit description, or skip
    │     Removed skills moved to ~/.skill-doctor/trash/ (recoverable with mv)
    │     Skills are never modified without explicit two-step confirmation
    │
    └── Phase 6: Hook Registration (first run, idempotent)
          Writes PostToolUse + UserPromptSubmit hooks to ~/.claude/settings.json
```

---

## State Files

All runtime state lives in `~/.skill-doctor/`:

```
~/.skill-doctor/
├── metadata-cache.json    # Skill metadata keyed by path
│                          # (name, version, mtime, checksum, summary, triggers, proactive, tools)
│                          # checksum = SHA-256 of SKILL.md; guards against mtime resets
├── known-conflicts.json   # User-acknowledged conflict suppressions
├── removals.jsonl         # Log of skills moved to trash
├── hook.lock              # Debounce lockfile (30s window)
├── reports/               # Saved scan reports (markdown)
│   └── {user}-{datetime}-scan.md
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

**Exit codes:** `0` = no critical conflicts; `1` = critical conflicts found

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
cd ~/.claude/skills/skill-doctor
git pull
./setup
```

skill-doctor checks for updates on each run via `bin/skill-doctor-update-check` (GitHub Releases API, silent on failure).

---

## License

MIT
