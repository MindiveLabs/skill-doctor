---
name: skill-doctor
version: 0.1.0
description: |
  Detects and resolves conflicts between installed Claude Code skills. Scans for
  7 conflict classes: name shadows, trigger collisions, semantic overlap, proactive
  races, state file collisions, tool permission conflicts, and subsumption.
  Recommends which skill to keep or remove for each conflict found.
  Use when asked to "check skill conflicts", "scan skills", "skill-doctor",
  "detect skill conflicts", or "fix skill conflicts".
  Proactively suggest when skill invocation behaves unexpectedly.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - AskUserQuestion
---

# skill-doctor

Detects and resolves conflicts between installed Claude Code skills.

---

## Preamble

Run this first:

```bash
_UPD=$(~/.claude/skills/skill-doctor/bin/skill-doctor-update-check 2>/dev/null || true)
[ -n "$_UPD" ] && echo "$_UPD" || true
mkdir -p ~/.config/skill-doctor/trash
_SD_VERSION=$(cat ~/.claude/skills/skill-doctor/VERSION 2>/dev/null || echo "0.1.0")
echo "skill-doctor v$_SD_VERSION"
```

If output contains `UPGRADE_AVAILABLE <old> <new>`: tell the user "skill-doctor
v{new} is available (current: v{old}). Run `~/.claude/skills/skill-doctor/setup`
to upgrade."

---

## Phase 1: Skill Discovery

Enumerate all installed skills:

```bash
# Personal skills
PERSONAL_SKILLS_DIR="${HOME}/.claude/skills"

# Project skills (current working directory)
PROJECT_SKILLS_DIR=".claude/skills"

# Collect all SKILL.md paths
SKILL_FILES=()

for dir in "$PERSONAL_SKILLS_DIR" "$PROJECT_SKILLS_DIR"; do
  if [[ -d "$dir" ]]; then
    while IFS= read -r -d '' f; do
      real=$(realpath "$f" 2>/dev/null || readlink -f "$f" 2>/dev/null || echo "$f")
      SKILL_FILES+=("$real")
    done < <(find "$dir" -name "SKILL.md" -print0 2>/dev/null)
  fi
done

# Also check settings.json for additional paths
SETTINGS="${HOME}/.claude/settings.json"
if [[ -f "$SETTINGS" ]] && command -v jq &>/dev/null; then
  while IFS= read -r extra_dir; do
    [[ -z "$extra_dir" ]] && continue
    while IFS= read -r -d '' f; do
      real=$(realpath "$f" 2>/dev/null || readlink -f "$f" 2>/dev/null || echo "$f")
      SKILL_FILES+=("$real")
    done < <(find "$extra_dir" -name "SKILL.md" -print0 2>/dev/null)
  done < <(jq -r '.skills.additionalDirectories[]? // empty' "$SETTINGS" 2>/dev/null)
fi

echo "Found ${#SKILL_FILES[@]} skill files"
for f in "${SKILL_FILES[@]}"; do echo "  $f"; done
```

Parse each SKILL.md to extract name, description, and version. Skip and warn for:
- Files with no YAML frontmatter (no `---` block)
- Files with missing `name:` field
- Files you can't read (permissions)

Print inventory:
```
Skill inventory:
  skill-name    v1.0.0    ~/.claude/skills/skill-name/SKILL.md
  ...
```

---

## Phase 2: Static Analysis

Run the static scanner:

```bash
~/.claude/skills/skill-doctor/bin/skill-doctor-scan --scope all > /tmp/sd-static.json 2>/tmp/sd-static.err
SCAN_EXIT=$?
cat /tmp/sd-static.err >&2 || true
```

Read `/tmp/sd-static.json`. It contains conflicts for Classes 1 (Name Shadow),
5 (State File Collision), and 6 (Tool Permission Conflict).

If scan fails or produces invalid JSON, warn: "Static scan failed — skipping
Classes 1/5/6. Proceeding with semantic analysis only."

---

## Phase 3: Semantic Analysis (Classes 2, 3, 4, 7)

### Step 1: Read/Update Metadata Cache

```bash
CACHE_FILE="${HOME}/.config/skill-doctor/metadata-cache.json"
mkdir -p "$(dirname "$CACHE_FILE")"
if [[ ! -f "$CACHE_FILE" ]]; then
  echo '{"schema_version":1,"skills":{}}' > "$CACHE_FILE"
fi
cat "$CACHE_FILE"
```

For each skill in the inventory:
1. Get the file's mtime: `stat -c %Y FILE 2>/dev/null || stat -f %m FILE`
2. Check if `path` + `mtime` matches the cache
3. For uncached or stale skills: generate a 1-line summary by reasoning about
   the skill's description (what does it do, in 8-15 words)
4. Write updated cache back

Cache entry format:
```json
{
  "schema_version": 1,
  "skills": {
    "/path/to/SKILL.md": {
      "name": "skill-name",
      "mtime": 1700000000,
      "summary": "8-15 word summary of what this skill does"
    }
  }
}
```

### Step 2: Semantic Conflict Detection

**Count the skills in inventory.** Use this strategy:

**If ≤80 skills (single-pass):**

Reason about all skills simultaneously. For each pair that may conflict, identify:

- **Class 2 (Trigger Collision)**: Overlapping "Use when asked to" or "Use when" phrases.
  Two skills have trigger phrases that would match the same user request. This means
  Claude would arbitrarily choose one or both, leading to confusing behavior.
  Example: skill-a triggers on "review my code" and skill-b also triggers on "review code".

- **Class 3 (Semantic Overlap)**: Same user intent, different descriptions. A user asking
  for help with the underlying task might invoke either skill. The skills don't share
  trigger phrases but solve the same problem.
  Example: "debug-helper" (root cause analysis) and "bug-fixer" (find and fix bugs).

- **Class 4 (Proactive Suggestion Race)**: Both skills have "Proactively suggest when"
  clauses that would fire simultaneously for the same user situation. This creates
  a "two doctors both giving advice" problem.
  Example: skill-a suggests when "tests fail" and skill-b suggests when "user sees an error".

- **Class 7 (Subsumption)**: One skill fully covers the other. Installing both is
  redundant — the subsumed skill is never the better choice.
  Example: "code-assistant" covers everything "snippet-writer" does plus more.

Report conflicts as JSON:
```json
[
  {
    "class": "2",
    "skill_a": "pr-review",
    "skill_b": "code-review",
    "severity": "HIGH",
    "reason": "Both trigger on 'code review' — ambiguous which skill runs",
    "recommendation": "Keep pr-review (more comprehensive); remove code-review"
  }
]
```

**If >80 skills (two-pass):**

*Pass 1:* Use the 1-line summaries (8-15 words each) to group semantically similar
skills. Skills in different groups cannot conflict. Identify groups with ≥2 skills.

*Pass 2:* For each group with ≥2 skills, analyze the full descriptions to detect
conflict classes 2, 3, 4, 7 as above.

*Merge:* Combine results from all groups. Deduplicate.

**Error handling:** If semantic analysis produces invalid JSON or fails entirely:
warn "Semantic analysis failed — showing static results only" and continue
with Phase 4 using only static results.

---

## Phase 4: Report

Merge static conflicts (from `/tmp/sd-static.json`) and semantic conflicts
(from Phase 3). Remove any conflicts listed in `~/.config/skill-doctor/known-conflicts.json`
(user-acknowledged suppressions). GC stale entries from known-conflicts.json
(skills that no longer exist).

Display the conflict map:

```
skill-doctor scan complete — X skills, Y conflicts found
═══════════════════════════════════════════════════════

CRITICAL (must resolve before skills work correctly):
  [1] pr-review ←→ code-review
      Class 1: Name Shadow — both named "my-skill"
      pr-review shadows code-review (personal > project scope)

HIGH:
  [2] pr-review ←→ code-review
      Class 2: Trigger Collision — both trigger on "code review"
      Recommendation: keep pr-review, remove code-review

MEDIUM:
  [3] hook-manager ←→ hook-cleaner
      Class 5: State Collision — both write ~/.claude/settings.json

LOW:
  [4] read-only-assistant ←→ safe-viewer
      Class 6: Tool Conflict — both have disable-model-invocation: true

───────────────────────────────────────────────────────
Run `/skill-doctor --fix` to interactively resolve these.
```

If no conflicts: "No conflicts found across X skills. ✓"

If `--fix` was NOT passed in the invocation: stop here and suggest
`/skill-doctor --fix`.

---

## Phase 5: Interactive Resolution

(Only runs when invoked as `/skill-doctor --fix` or user says "fix", "resolve", etc.)

For each conflict (in severity order: CRITICAL first), use AskUserQuestion:

Present:
- Conflict number and class name
- skill_a and skill_b: names and file paths
- The reason (why this is a conflict)
- The recommendation (which to keep)

Options:
```
A) Keep [skill_a], remove [skill_b]  — [recommendation if applicable]
B) Keep [skill_b], remove [skill_a]  — [recommendation if applicable]
C) Mark as intentional (suppress future warnings)
D) Edit skill content to resolve (I'll propose minimal description changes)
E) Skip for now
```

**Important:** Do NOT suggest modifying skill content unless the user explicitly
chooses option D. The default recommendation is always keep/remove.

**If A or B chosen:**
1. Move the removed skill's directory to trash:
   ```bash
   SKILL_DIR=$(dirname PATH_TO_SKILL_MD)
   SKILL_NAME=$(basename "$SKILL_DIR")
   TRASH_DEST="${HOME}/.config/skill-doctor/trash/${SKILL_NAME}-$(date +%s)"
   mv "$SKILL_DIR" "$TRASH_DEST"
   ```
2. Log to removals.jsonl:
   ```bash
   echo '{"schema_version":1,"name":"SKILL_NAME","path":"ORIGINAL_PATH","trashed_at":"TIMESTAMP","conflict_class":"CLASS"}' \
     >> ~/.config/skill-doctor/removals.jsonl
   ```
3. Confirm: "Moved [skill_name] to trash at $TRASH_DEST. Restore with: mv '$TRASH_DEST' 'ORIGINAL_PARENT/'"

**If C chosen:**
Append to known-conflicts.json:
```bash
python3 -c "
import json, sys, os
f = os.path.expanduser('~/.config/skill-doctor/known-conflicts.json')
try:
    with open(f) as fh: d = json.load(fh)
except: d = {'schema_version': 1, 'conflicts': []}
d.setdefault('conflicts', []).append({
    'skill_a': 'SKILL_A', 'skill_b': 'SKILL_B',
    'class': 'CLASS', 'ts': 'TIMESTAMP'
})
with open(f, 'w') as fh: json.dump(d, fh, indent=2)
"
```

**If D chosen:**
Propose a minimal edit to one skill's description that eliminates the conflict
(e.g., narrow a trigger phrase, clarify scope). Show the diff. Ask for approval
before touching the file.

**After all conflicts resolved:** Re-run Phases 2+3 to confirm clean state.

---

## Phase 6: Hook Registration

(Runs on first-ever invocation. Idempotent — safe to re-run.)

Skip if `--scope local` was passed.

Check for existing hook registration:

```bash
SETTINGS="${HOME}/.claude/settings.json"
if [[ -f "$SETTINGS" ]]; then
  if grep -q "skill-doctor" "$SETTINGS" 2>/dev/null; then
    echo "HOOKS_ALREADY_REGISTERED"
  else
    echo "HOOKS_NOT_REGISTERED"
  fi
else
  echo "SETTINGS_NOT_FOUND"
fi
```

If `HOOKS_ALREADY_REGISTERED`: skip silently.

If `HOOKS_NOT_REGISTERED` or `SETTINGS_NOT_FOUND`:

Attempt to write hooks to settings.json. Read the current settings first:

```bash
cat "${HOME}/.claude/settings.json" 2>/dev/null || echo '{}'
```

Add these two hook entries to the `hooks` array (or create it):

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "bash -c 'echo \"$CLAUDE_TOOL_INPUT\" | grep -q \"SKILL.md\" && ~/.claude/skills/skill-doctor/bin/skill-doctor-hook || true'",
            "description": "skill-doctor: detect skill conflicts after SKILL.md edits"
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/skills/skill-doctor/bin/skill-doctor-hook --session-start",
            "description": "skill-doctor: check for skill conflicts at session start"
          }
        ]
      }
    ]
  }
}
```

Write atomically: write to `.settings.json.tmp`, then rename to `settings.json`.
Back up first: `cp settings.json settings.json.bak`.

Validate JSON after write:
```bash
python3 -c "import json; json.load(open('${HOME}/.claude/settings.json'))" && echo "JSON_VALID" || echo "JSON_INVALID"
```

If write fails or JSON is invalid: restore backup and print manual config for
the user to add themselves:

```
Could not automatically register hooks. Add these to ~/.claude/settings.json:

[paste hook JSON above]
```

On success: "Hooks registered. skill-doctor will now alert you when skills conflict."
