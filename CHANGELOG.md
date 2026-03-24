# Changelog

All notable changes to skill-doctor are documented here.

## [0.3.1] - 2026-03-24

### Changed
- Static analysis output now written to `~/.skill-doctor/` instead of `/tmp`, keeping all runtime state in one place
- README overhauled: added "Why You Need This" section, condensed How It Works diagram, one-line install command, cleaner Interactive Resolution example
- Upgrading section now leads with auto-upgrade behavior; manual trigger via `/skill-doctor upgrade yourself`

## [0.3.0] - 2026-03-18

### Added
- Self-upgrade support: `/skill-doctor upgrade yourself` pulls latest version and re-runs setup
- `bin/skill-doctor-update-check` checks GitHub Releases API on each run; notifies when a newer version is available
- `bin/skill-doctor-upgrade` script handles the upgrade flow

## [0.2.0] - 2026-03-17

### Added
- Metadata cache with mtime fast-path and SHA-256 checksum for change detection
- Two-pass semantic analysis for installations with >80 skills
- Hook registration (PostToolUse + UserPromptSubmit) on first run
- Full test suite: static.test.sh (8), hook.test.sh (12), upgrade.test.sh (26)

### Changed
- Conflict report uses human-readable names (no internal class numbers)
- Known-conflicts.json suppressions applied before displaying report

## [0.1.0] - 2026-03-10

### Added
- Initial release: 7 conflict classes, static scanner, semantic analysis, interactive resolution
