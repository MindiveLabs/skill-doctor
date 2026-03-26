# skill-doctor

A [Claude Code](https://claude.ai/claude-code) skill that detects and resolves conflicts between installed skills.

When you have multiple skills installed, some may shadow each other, collide on triggers, or race to make proactive suggestions. skill-doctor scans your skill inventory, tells you what could possibly go wrong, and helps you fix it — safely.

**Read-only by default.** skill-doctor never modifies skill files directly. The only action it takes (with your explicit confirmation) is moving a conflicting skill to trash — always recoverable.

---

## Installation

### Plugin (recommended)

```
/plugin marketplace add MindiveLabs/skill-doctor
/plugin install skill-doctor@skill-doctor
```

Hooks are registered automatically. Upgrade anytime with `/plugin update skill-doctor@skill-doctor`.

### Standalone (git clone)

```bash
git clone git@github.com:MindiveLabs/skill-doctor.git ~/.claude/skills/skill-doctor && ~/.claude/skills/skill-doctor/setup
```

Hook registration (background scanning on skill changes) happens automatically on the first `/skill-doctor` run. Upgrade with `/skill-doctor upgrade yourself`.

---

## Usage (in your Claude Code)

```
/skill-doctor           — scan and report conflicts
/skill-doctor --fix     — scan and interactively resolve each conflict
```

On first run, skill-doctor registers two background hooks that watch for changes and alert you when critical conflicts appear. They never block.

Each scan saves a full markdown report to `~/.skill-doctor/reports/`.

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
    │     Detects: Name Shadow, State File Collision, Tool Conflict
    │
    ├── Phase 3: Semantic Analysis
    │     Detects: Trigger Collision, Semantic Overlap, Proactive Race, Subsumption
    │
    ├── Phase 4: Report
    │     Shows conflict map by severity, saves full report to ~/.skill-doctor/reports/
    │
    ├── Phase 5: Interactive Resolution (--fix only)
    │     Fixes the conclicts. Removed skills moved to ~/.skill-doctor/trash/ (recoverable with mv)
```

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

---

## Interactive Resolution

When you run `/skill-doctor --fix`, each conflict is presented one at a time with context and a clear recommendation:

```
[2] pr-review ←→ code-review
    Trigger Collision — both trigger on "code review"
    Recommendation: keep pr-review, remove code-review

A) Keep pr-review, remove code-review  (moved to trash — recoverable)
B) Keep code-review, remove pr-review  (moved to trash — recoverable)
C) Mark as intentional (suppress future warnings)
D) Edit a skill's description to resolve
E) Skip for now
```

Removed skills are moved to `~/.skill-doctor/trash/` and can be restored with a single `mv` command.

---

## Tests

```bash
cd test
./static.test.sh    # static scanner
./hook.test.sh      # hook debounce and advisory output
./upgrade.test.sh   # setup and update-check scripts
```

---

## Upgrading

skill-doctor checks for updates on every run and notifies you when a new version is available.

**Plugin install:** run `/plugin update skill-doctor@skill-doctor` in any Claude Code session.

**Standalone install:** run `/skill-doctor upgrade yourself` to upgrade in place.

---

## License

MIT
