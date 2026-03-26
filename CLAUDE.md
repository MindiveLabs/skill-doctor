# skill-doctor development

## Commands

```bash
./setup                  # install to ~/.claude/skills/skill-doctor/
bash test/static.test.sh  # 8 tests for the static scanner
bash test/hook.test.sh    # 12 tests for the hook (debounce, exit codes, advisory)
bash test/upgrade.test.sh # 26 tests for setup and update-check
```

Run all tests at once:

```bash
bash test/static.test.sh && bash test/hook.test.sh && bash test/upgrade.test.sh
```

All 46 tests must pass before committing. Tests run on bash 3.2+ (macOS default) — no dependencies required.

## Project structure

```
skill-doctor/
├── .claude-plugin/
│   ├── plugin.json            # Plugin manifest (name, version, author)
│   └── marketplace.json       # Marketplace catalog (lists this plugin)
├── hooks/
│   └── hooks.json             # Plugin hooks — auto-registered for plugin installs
├── skills/
│   └── skill-doctor/
│       ├── SKILL.md           # The skill prompt (version: must match VERSION)
│       ├── VERSION            # Current version (single source of truth)
│       └── bin/
│           ├── skill-doctor-scan          # Static conflict scanner (bash, no LLM)
│           ├── skill-doctor-hook          # PostToolUse/UserPromptSubmit hook handler
│           ├── skill-doctor-update-check  # GitHub Releases API version check
│           └── skill-doctor-upgrade       # Self-upgrade script (standalone only)
├── test/
│   ├── fixtures/                  # Synthetic SKILL.md files for scanner tests
│   ├── static.test.sh             # Tests for skill-doctor-scan
│   ├── hook.test.sh               # Tests for skill-doctor-hook
│   └── upgrade.test.sh            # Tests for setup + update-check
├── setup                          # Install script: copies skill files to ~/.claude/skills/skill-doctor/
└── CHANGELOG.md                   # User-facing release notes
```

## Install methods

**Plugin (marketplace)** — hooks registered automatically, upgrades via `/plugin update`:
```
/plugin marketplace add MindiveLabs/skill-doctor
/plugin install skill-doctor@skill-doctor
```

**Standalone (git clone + setup)** — hooks registered on first `/skill-doctor` run, upgrades via `/skill-doctor upgrade yourself`:
```bash
git clone git@github.com:MindiveLabs/skill-doctor.git ~/.claude/skills/skill-doctor
~/.claude/skills/skill-doctor/setup
```

## Versioning

`skills/skill-doctor/VERSION` and `skills/skill-doctor/SKILL.md` (the `version:` frontmatter field) **must always match**. Bump both together — never one without the other. Also bump the version in `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`. The `setup` script copies both files to the install directory; a mismatch means the installed skill reports the wrong version.

Version format: `MAJOR.MINOR.PATCH`

| Bump | When |
|------|------|
| PATCH | Bug fixes, doc updates, internal path changes |
| MINOR | New conflict class, new phase, user-visible feature |
| MAJOR | Breaking change, major architectural overhaul |

When bumping:
1. Update `skills/skill-doctor/VERSION`
2. Update `version:` in `skills/skill-doctor/SKILL.md` frontmatter
3. Update `version` in `.claude-plugin/plugin.json`
4. Update `version` in `.claude-plugin/marketplace.json` (plugin entry)
5. Add a CHANGELOG entry (see CHANGELOG style below)

## CHANGELOG style

Write for users, not contributors. Every entry should describe what the user can now do — not what was refactored internally.

- Lead with user-visible impact. "Static analysis results are now..." not "Changed output path from..."
- Use plain language. Avoid internal terminology (phase numbers, class IDs, variable names).
- Keep contributor/internal notes out of the main sections. Add a "For contributors" section at the bottom if needed.
- Date format: `YYYY-MM-DD`
- Header format: `## [X.Y.Z] - YYYY-MM-DD`

## Commit style

One logical change per commit. Good examples:
- Static scanner fix separate from its test update
- SKILL.md prompt change separate from bin/ script change
- VERSION + CHANGELOG always in the final commit of a branch

## Deploying your changes

After editing, reinstall to pick up changes in the active skill:

```bash
./setup
```

This copies `SKILL.md`, `VERSION`, and all `bin/` scripts from `skills/skill-doctor/` to `~/.claude/skills/skill-doctor/`. Changes are live immediately in any new Claude Code session.

## Testing philosophy

The test suite uses only bash and temp directories — no external dependencies, no network, no LLM. Tests are fast (<5s total) and safe to run anywhere.

When adding a new feature to `skills/skill-doctor/bin/`:
- Add fixtures to `test/fixtures/` if the feature needs synthetic SKILL.md inputs
- Add test cases to the relevant `.test.sh` file
- Test both the happy path and failure/edge cases (malformed input, missing files, permission errors)
