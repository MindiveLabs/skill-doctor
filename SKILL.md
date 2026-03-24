---
name: skill-doctor
version: 0.3.0
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
  - AskUserQuestion
---

# skill-doctor

Detects and resolves conflicts between installed Claude Code skills.

**Read-only by default.** skill-doctor never modifies skill files unless the user
explicitly asks. All analysis is non-destructive. Removals move to trash (recoverable).

---

## Preamble

Run this first:

```bash
_UPD=$(~/.claude/skills/skill-doctor/bin/skill-doctor-update-check 2>/dev/null || true)
[ -n "$_UPD" ] && echo "$_UPD" || true
mkdir -p ~/.skill-doctor/trash ~/.skill-doctor/reports
_SD_VERSION=$(cat ~/.claude/skills/skill-doctor/VERSION 2>/dev/null || echo "0.1.0")
echo "skill-doctor v$_SD_VERSION"
```

If output contains `UPGRADE_AVAILABLE <old> <new>`: tell the user "skill-doctor
v{new} is available (current: v{old}). Run `/skill-doctor upgrade yourself` to upgrade."

**If arguments contain "upgrade" or "upgrade yourself":** run the upgrade script:

```bash
~/.claude/skills/skill-doctor/bin/skill-doctor-upgrade
```

Show the output. If it succeeds, tell the user the upgrade is complete, then
**automatically proceed to Phase 1** to run the scan with the upgraded version.
If it fails, show the error and stop.

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
mkdir -p ~/.skill-doctor
~/.claude/skills/skill-doctor/bin/skill-doctor-scan --scope all > ~/.skill-doctor/sd-static.json 2>~/.skill-doctor/sd-static.err
SCAN_EXIT=$?
cat ~/.skill-doctor/sd-static.err >&2 || true
```

Read `~/.skill-doctor/sd-static.json`. It contains conflicts for Name Shadow, State File Collision,
and Tool Permission Conflict.

If scan fails or produces invalid JSON, warn: "Static scan failed — skipping
static checks. Proceeding with semantic analysis only."

---

## Phase 3: Metadata Cache + Semantic Analysis

### Step 1: Read/Update Metadata Cache

```bash
CACHE_FILE="${HOME}/.skill-doctor/metadata-cache.json"
mkdir -p "$(dirname "$CACHE_FILE")"
if [[ ! -f "$CACHE_FILE" ]]; then
  echo '{"schema_version":1,"skills":{}}' > "$CACHE_FILE"
fi
cat "$CACHE_FILE"
```

For each skill in the inventory, use a two-stage cache check:

**Stage 1 — mtime (fast path):**
```bash
# Get current mtime
mtime=$(stat -c %Y "$skill_file" 2>/dev/null || stat -f %m "$skill_file" 2>/dev/null || echo "0")
```
If the cache entry exists and `mtime` matches → skip this skill entirely. Content
hasn't changed; no checksum or regeneration needed.

**Stage 2 — checksum (mtime changed or no cache entry):**
```bash
# Compute SHA-256 of the file content (macOS and Linux compatible)
checksum=$(shasum -a 256 "$skill_file" 2>/dev/null | awk '{print $1}' || \
           sha256sum "$skill_file" 2>/dev/null | awk '{print $1}' || echo "")
```
Compare `checksum` to the cached value:
- **Matches** → file was touched (git checkout, rsync, etc.) but content is unchanged.
  Update only the `mtime` field in the cache entry. Skip regeneration.
- **Differs or missing** → content genuinely changed. Regenerate metadata:
  - Read the full SKILL.md frontmatter
  - Extract: trigger phrases ("Use when asked to...", "Use when..."),
    proactive clauses ("Proactively suggest when..."), and allowed-tools list
  - Generate a rich summary: 1–3 sentences describing what the skill does,
    what it doesn't do, and when to invoke it (max 300 characters)
  - Write the full updated entry (including new `mtime` and `checksum`) to the cache

Write updated cache back to disk after processing all skills.

Cache entry format:
```json
{
  "schema_version": 1,
  "skills": {
    "/path/to/SKILL.md": {
      "name": "skill-name",
      "version": "1.0.0",
      "mtime": 1700000000,
      "checksum": "a3f1c2d4e5b6...",
      "summary": "Up to 300-char rich description of what this skill does, when to use it, and what it does not do.",
      "triggers": ["review my code", "code review"],
      "proactive": ["when tests fail", "when the user reports an error"],
      "tools": ["Bash", "Read"]
    }
  }
}
```

`checksum` is a SHA-256 hex digest of the SKILL.md file contents. It is the
authoritative signal for whether metadata needs regeneration. `mtime` is a
cheap pre-check that avoids computing checksums on every invocation.

### Step 2: Semantic Conflict Detection

**Count the skills in inventory.** Use this strategy:

**If ≤80 skills (single-pass):**

Reason about all skills simultaneously using the cached summaries and trigger phrases.
For each pair that may conflict, identify:

- **Trigger Collision**: Overlapping "Use when asked to" or "Use when" phrases.
  Two skills have trigger phrases that would match the same user request. Claude would
  arbitrarily choose one or both, leading to confusing behavior.
  Example: skill-a triggers on "review my code" and skill-b also triggers on "review code".

- **Semantic Overlap**: Same user intent, different descriptions. A user asking
  for help with the underlying task might invoke either skill. The skills don't share
  trigger phrases but solve the same problem.
  Example: "debug-helper" (root cause analysis) and "bug-fixer" (find and fix bugs).

- **Proactive Suggestion Race**: Both skills have "Proactively suggest when"
  clauses that would fire simultaneously for the same user situation.
  Example: skill-a suggests when "tests fail" and skill-b suggests when "user sees an error".

- **Subsumption**: One skill fully covers the other. Installing both is
  redundant — the subsumed skill is never the better choice.
  Example: "code-assistant" covers everything "snippet-writer" does plus more.

Report conflicts as JSON:
```json
[
  {
    "type": "trigger-collision",
    "skill_a": "pr-review",
    "skill_b": "code-review",
    "severity": "HIGH",
    "reason": "Both trigger on 'code review' — ambiguous which skill runs",
    "recommendation": "Keep pr-review (more comprehensive); remove code-review"
  }
]
```

**If >80 skills (two-pass):**

*Pass 1:* Use the cached summaries to group semantically similar skills.
Skills in different groups cannot conflict. Identify groups with ≥2 skills.

*Pass 2:* For each group with ≥2 skills, analyze using full cached metadata to detect
all four semantic conflict types above.

*Merge:* Combine results from all groups. Deduplicate.

**Error handling:** If semantic analysis produces invalid JSON or fails entirely:
warn "Semantic analysis failed — showing static results only" and continue
with Phase 4 using only static results.

---

## Phase 4: Report

Merge static conflicts (from `~/.skill-doctor/sd-static.json`) and semantic conflicts
(from Phase 3). Remove any conflicts listed in `~/.skill-doctor/known-conflicts.json`
(user-acknowledged suppressions). GC stale entries from known-conflicts.json
(skills that no longer exist).

Display the conflict map using human-readable names only (no internal class numbers):

```
skill-doctor scan complete — X skills, Y conflicts found
═══════════════════════════════════════════════════════

Must resolve (skills may not work correctly):
  [1] pr-review ←→ code-review
      Name Shadow — both skills have the same name
      pr-review takes precedence (personal scope > project scope)
      → Remove code-review to fix

High priority:
  [2] pr-review ←→ code-review
      Trigger Collision — both trigger on "code review"
      → Recommendation: keep pr-review, remove code-review

Medium priority:
  [3] hook-manager ←→ hook-cleaner
      State File Collision — both read/write ~/.claude/settings.json

Low priority:
  [4] read-only-assistant ←→ safe-viewer
      Tool Conflict — both restrict model invocation

───────────────────────────────────────────────────────
Run `/skill-doctor --fix` to interactively resolve these.
```

If no conflicts: "No conflicts found across X skills. ✓"

### Save Report

Save the full report to disk and show the path:

```bash
REPORT_USER=$(whoami)
REPORT_TS=$(date +%Y%m%d-%H%M%S)
REPORT_FILE="${HOME}/.skill-doctor/reports/${REPORT_USER}-${REPORT_TS}-scan.md"
mkdir -p "${HOME}/.skill-doctor/reports"
```

Write a markdown report to `$REPORT_FILE` containing:
- Timestamp (date and time) and skill-doctor version
- Skill inventory (names, paths, scopes)
- Full conflict list with reasons and recommendations
- Any warnings (skipped/malformed skills)

Tell the user: "Report saved to `$REPORT_FILE`"

If `--fix` was NOT passed in the invocation: stop here and suggest
`/skill-doctor --fix`.

---

## Phase 5: Interactive Resolution

(Only runs when invoked as `/skill-doctor --fix` or user says "fix", "resolve", etc.)

**skill-doctor is read-only.** It analyzes and reports. The only actions here are:
- Moving a skill directory to trash (reversible)
- Suppressing a known-intentional conflict
- Optionally editing a skill's description (only when user explicitly requests it)

For each conflict (in severity order: critical first), use AskUserQuestion:

Present:
- The two skill names and their file paths
- The conflict type (human-readable name)
- The reason this is a conflict
- The recommendation (which to keep)

Options:
```
A) Keep [skill_a], remove [skill_b]  — moves skill_b to trash (recoverable)
B) Keep [skill_b], remove [skill_a]  — moves skill_a to trash (recoverable)
C) Mark as intentional (suppress future warnings)
D) Edit a skill's description to resolve (I'll propose the minimal change for approval)
E) Skip for now
```

**If A or B chosen:**
1. Move the removed skill's directory to trash:
   ```bash
   SKILL_DIR=$(dirname PATH_TO_SKILL_MD)
   SKILL_NAME=$(basename "$SKILL_DIR")
   TRASH_DEST="${HOME}/.skill-doctor/trash/${SKILL_NAME}-$(date +%s)"
   mv "$SKILL_DIR" "$TRASH_DEST"
   ```
2. Log to removals.jsonl:
   ```bash
   echo '{"schema_version":1,"name":"SKILL_NAME","path":"ORIGINAL_PATH","trashed_at":"TIMESTAMP","conflict_type":"TYPE"}' \
     >> ~/.skill-doctor/removals.jsonl
   ```
3. Confirm: "Moved [skill_name] to trash at $TRASH_DEST. Restore anytime with:
   `mv '$TRASH_DEST' 'ORIGINAL_PARENT/'`"

**If C chosen:**
Append to known-conflicts.json:
```bash
python3 -c "
import json, sys, os
f = os.path.expanduser('~/.skill-doctor/known-conflicts.json')
try:
    with open(f) as fh: d = json.load(fh)
except: d = {'schema_version': 1, 'conflicts': []}
d.setdefault('conflicts', []).append({
    'skill_a': 'SKILL_A', 'skill_b': 'SKILL_B',
    'type': 'TYPE', 'ts': 'TIMESTAMP'
})
with open(f, 'w') as fh: json.dump(d, fh, indent=2)
"
```

**If D chosen (explicit user request only):**
Propose a minimal edit to one skill's description that eliminates the conflict
(e.g., narrow a trigger phrase, clarify scope). Show the exact diff. Ask for
explicit approval before touching any file. Never modify skill files without this
two-step confirmation.

**After all conflicts resolved:** Re-run Phases 2+3 to confirm clean state.
Save a new report and show the path.

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
