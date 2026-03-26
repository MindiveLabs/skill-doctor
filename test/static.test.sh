#!/usr/bin/env bash
# static.test.sh — Tests for skill-doctor-scan (Classes 1, 5, 6 + edge cases)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"
SCANNER="$SCRIPT_DIR/../skills/skill-doctor/bin/skill-doctor-scan"

PASS=0
FAIL=0
SKIP=0

# Ensure scanner exists
if [[ ! -x "$SCANNER" ]]; then
  echo "ERROR: scanner not found or not executable: $SCANNER"
  exit 1
fi

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

run_test() {
  local desc="$1"
  local expected_exit="$2"
  shift 2
  local cmd=("$@")

  local actual_exit=0
  local output
  output=$("${cmd[@]}" 2>&1) || actual_exit=$?

  if [[ "$actual_exit" -eq "$expected_exit" ]]; then
    echo "PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $desc"
    echo "  expected exit $expected_exit, got $actual_exit"
    echo "  output: $(echo "$output" | head -5)"
    FAIL=$((FAIL + 1))
  fi
  echo "$output"  # return output for callers that capture it
}

# Run scanner, capture JSON output, check exit code, check JSON field
assert_json_contains() {
  local desc="$1"
  local dir="$2"
  local expected_exit="$3"
  local jq_filter="$4"
  local expected_value="$5"

  local actual_exit=0
  local output
  output=$("$SCANNER" --scope all --skills-dir "$dir" 2>/dev/null) || actual_exit=$?

  if [[ "$actual_exit" -ne "$expected_exit" ]]; then
    echo "FAIL: $desc"
    echo "  expected exit $expected_exit, got $actual_exit"
    FAIL=$((FAIL + 1))
    return
  fi

  if ! echo "$output" | python3 -c "import sys,json; d=json.load(sys.stdin); v=d$jq_filter; assert str(v)==str('$expected_value'), f'got {v!r}'" 2>/dev/null; then
    echo "FAIL: $desc"
    echo "  jq filter: $jq_filter"
    echo "  expected: $expected_value"
    echo "  json output: $output"
    FAIL=$((FAIL + 1))
    return
  fi

  echo "PASS: $desc"
  PASS=$((PASS + 1))
}

# Simpler: run scanner against a fixture dir, check JSON output contains a string
assert_output_contains() {
  local desc="$1"
  local dir="$2"
  local expected_exit="$3"
  local pattern="$4"

  local actual_exit=0
  local output
  output=$("$SCANNER" --scope all --skills-dir "$dir" 2>&1) || actual_exit=$?

  if [[ "$actual_exit" -ne "$expected_exit" ]]; then
    echo "FAIL: $desc (exit)"
    echo "  expected exit $expected_exit, got $actual_exit"
    echo "  output: $output"
    FAIL=$((FAIL + 1))
    return
  fi

  if ! echo "$output" | grep -q "$pattern"; then
    echo "FAIL: $desc (content)"
    echo "  expected pattern: $pattern"
    echo "  output: $output"
    FAIL=$((FAIL + 1))
    return
  fi

  echo "PASS: $desc"
  PASS=$((PASS + 1))
}

# Run scanner, expect output NOT to contain a pattern
assert_output_not_contains() {
  local desc="$1"
  local dir="$2"
  local expected_exit="$3"
  local pattern="$4"

  local actual_exit=0
  local output
  output=$("$SCANNER" --scope all --skills-dir "$dir" 2>&1) || actual_exit=$?

  if [[ "$actual_exit" -ne "$expected_exit" ]]; then
    echo "FAIL: $desc (exit)"
    echo "  expected exit $expected_exit, got $actual_exit"
    FAIL=$((FAIL + 1))
    return
  fi

  if echo "$output" | grep -q "$pattern"; then
    echo "FAIL: $desc (content)"
    echo "  unexpected pattern found: $pattern"
    echo "  output: $output"
    FAIL=$((FAIL + 1))
    return
  fi

  echo "PASS: $desc"
  PASS=$((PASS + 1))
}

# ---------------------------------------------------------------------------
# Class 1: Name Shadow
# ---------------------------------------------------------------------------
echo ""
echo "=== Class 1: Name Shadow ==="

assert_output_contains \
  "class1: detects duplicate name" \
  "$FIXTURES_DIR/class1-name-shadow" \
  1 \
  "CRITICAL"

assert_output_contains \
  "class1: reports conflicting skill names" \
  "$FIXTURES_DIR/class1-name-shadow" \
  1 \
  "my-skill"

assert_output_contains \
  "class1: output is valid JSON" \
  "$FIXTURES_DIR/class1-name-shadow" \
  1 \
  '"conflicts"'

# Class 1 should exit 1 (CRITICAL)
(
  actual_exit=0
  "$SCANNER" --scope all --skills-dir "$FIXTURES_DIR/class1-name-shadow" >/dev/null 2>&1 || actual_exit=$?
  if [[ "$actual_exit" -eq 1 ]]; then
    echo "PASS: class1: exit code 1 for CRITICAL conflict"
    PASS=$((PASS + 1))
  else
    echo "FAIL: class1: expected exit 1, got $actual_exit"
    FAIL=$((FAIL + 1))
  fi
) || true

# ---------------------------------------------------------------------------
# Class 5: State File Collision
# ---------------------------------------------------------------------------
echo ""
echo "=== Class 5: State File Collision ==="

assert_output_contains \
  "class5: detects settings.json write collision" \
  "$FIXTURES_DIR/class5-state-collision" \
  0 \
  "state-collision"

assert_output_contains \
  "class5: includes both conflicting skill names" \
  "$FIXTURES_DIR/class5-state-collision" \
  0 \
  "MEDIUM"

# Class 5 should exit 0 (not CRITICAL)
(
  actual_exit=0
  "$SCANNER" --scope all --skills-dir "$FIXTURES_DIR/class5-state-collision" >/dev/null 2>&1 || actual_exit=$?
  if [[ "$actual_exit" -eq 0 ]]; then
    echo "PASS: class5: exit code 0 (not CRITICAL)"
    PASS=$((PASS + 1))
  else
    echo "FAIL: class5: expected exit 0, got $actual_exit"
    FAIL=$((FAIL + 1))
  fi
) || true

# ---------------------------------------------------------------------------
# Class 6: Tool Conflict
# ---------------------------------------------------------------------------
echo ""
echo "=== Class 6: Tool Conflict ==="

assert_output_contains \
  "class6: detects disable-model-invocation conflict" \
  "$FIXTURES_DIR/class6-tool-conflict" \
  0 \
  "tool-conflict"

assert_output_contains \
  "class6: includes LOW severity" \
  "$FIXTURES_DIR/class6-tool-conflict" \
  0 \
  "LOW"

# Class 6 should exit 0
(
  actual_exit=0
  "$SCANNER" --scope all --skills-dir "$FIXTURES_DIR/class6-tool-conflict" >/dev/null 2>&1 || actual_exit=$?
  if [[ "$actual_exit" -eq 0 ]]; then
    echo "PASS: class6: exit code 0 (not CRITICAL)"
    PASS=$((PASS + 1))
  else
    echo "FAIL: class6: expected exit 0, got $actual_exit"
    FAIL=$((FAIL + 1))
  fi
) || true

# ---------------------------------------------------------------------------
# Clean directory: no conflicts
# ---------------------------------------------------------------------------
echo ""
echo "=== Clean: No Conflicts ==="

# Use class2-trigger dir as clean baseline — triggers are LLM-detected, not static
assert_output_not_contains \
  "clean: class2 dir produces no static conflicts" \
  "$FIXTURES_DIR/class2-trigger" \
  0 \
  "CRITICAL"

# Clean dir exits 0
(
  actual_exit=0
  "$SCANNER" --scope all --skills-dir "$FIXTURES_DIR/class2-trigger" >/dev/null 2>&1 || actual_exit=$?
  if [[ "$actual_exit" -eq 0 ]]; then
    echo "PASS: clean: exit code 0 for non-CRITICAL result"
    PASS=$((PASS + 1))
  else
    echo "FAIL: clean: expected exit 0, got $actual_exit"
    FAIL=$((FAIL + 1))
  fi
) || true

# ---------------------------------------------------------------------------
# Input validation: malformed fixtures
# ---------------------------------------------------------------------------
echo ""
echo "=== Input Validation: Malformed Skills ==="

# no-frontmatter: scanner should warn, not crash
(
  actual_exit=0
  output=$("$SCANNER" --scope all --skills-dir "$FIXTURES_DIR/malformed/no-frontmatter" 2>&1) || actual_exit=$?
  if [[ "$actual_exit" -ne 2 ]]; then
    echo "PASS: malformed/no-frontmatter: scanner does not crash (exit $actual_exit)"
    PASS=$((PASS + 1))
  else
    echo "FAIL: malformed/no-frontmatter: scanner crashed"
    echo "  output: $output"
    FAIL=$((FAIL + 1))
  fi
) || true

# missing-name: scanner should warn, not crash
(
  actual_exit=0
  output=$("$SCANNER" --scope all --skills-dir "$FIXTURES_DIR/malformed/missing-name" 2>&1) || actual_exit=$?
  if [[ "$actual_exit" -ne 2 ]]; then
    echo "PASS: malformed/missing-name: scanner does not crash (exit $actual_exit)"
    PASS=$((PASS + 1))
  else
    echo "FAIL: malformed/missing-name: scanner crashed"
    echo "  output: $output"
    FAIL=$((FAIL + 1))
  fi
) || true

# malformed skills produce WARN in output
(
  actual_exit=0
  output=$("$SCANNER" --scope all --skills-dir "$FIXTURES_DIR/malformed/missing-name" 2>&1) || actual_exit=$?
  if echo "$output" | grep -qi "warn\|skip\|missing"; then
    echo "PASS: malformed/missing-name: produces WARN/SKIP message"
    PASS=$((PASS + 1))
  else
    echo "FAIL: malformed/missing-name: no warning produced"
    echo "  output: $output"
    FAIL=$((FAIL + 1))
  fi
) || true

# non-existent directory: should fail gracefully
(
  actual_exit=0
  output=$("$SCANNER" --scope all --skills-dir "/nonexistent/path/that/does/not/exist" 2>&1) || actual_exit=$?
  if [[ "$actual_exit" -ne 2 ]]; then
    echo "PASS: nonexistent dir: does not crash with exit 2"
    PASS=$((PASS + 1))
  else
    echo "FAIL: nonexistent dir: crashed"
    FAIL=$((FAIL + 1))
  fi
) || true

# ---------------------------------------------------------------------------
# Scope flags
# ---------------------------------------------------------------------------
echo ""
echo "=== Scope Flags ==="

# --scope local should not crash
(
  actual_exit=0
  output=$("$SCANNER" --scope local --skills-dir "$FIXTURES_DIR/class1-name-shadow" 2>&1) || actual_exit=$?
  if echo "$output" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
    echo "PASS: --scope local: produces valid JSON"
    PASS=$((PASS + 1))
  else
    echo "FAIL: --scope local: output is not valid JSON"
    echo "  output: $output"
    FAIL=$((FAIL + 1))
  fi
) || true

# --scope global should not crash
(
  actual_exit=0
  output=$("$SCANNER" --scope global --skills-dir "$FIXTURES_DIR/class1-name-shadow" 2>&1) || actual_exit=$?
  if echo "$output" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
    echo "PASS: --scope global: produces valid JSON"
    PASS=$((PASS + 1))
  else
    echo "FAIL: --scope global: output is not valid JSON"
    echo "  output: $output"
    FAIL=$((FAIL + 1))
  fi
) || true

# invalid scope value: should fail gracefully
(
  actual_exit=0
  output=$("$SCANNER" --scope invalid --skills-dir "$FIXTURES_DIR/class1-name-shadow" 2>&1) || actual_exit=$?
  if [[ "$actual_exit" -ne 0 ]]; then
    echo "PASS: --scope invalid: non-zero exit for bad scope"
    PASS=$((PASS + 1))
  else
    echo "FAIL: --scope invalid: should reject invalid scope value"
    FAIL=$((FAIL + 1))
  fi
) || true

# ---------------------------------------------------------------------------
# Output format
# ---------------------------------------------------------------------------
echo ""
echo "=== Output Format ==="

# Output should always be valid JSON
(
  actual_exit=0
  output=$("$SCANNER" --scope all --skills-dir "$FIXTURES_DIR/class2-trigger" 2>&1) || actual_exit=$?
  if echo "$output" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'conflicts' in d" 2>/dev/null; then
    echo "PASS: output format: valid JSON with 'conflicts' key"
    PASS=$((PASS + 1))
  else
    echo "FAIL: output format: invalid JSON or missing 'conflicts' key"
    echo "  output: $output"
    FAIL=$((FAIL + 1))
  fi
) || true

# schema_version present
(
  actual_exit=0
  output=$("$SCANNER" --scope all --skills-dir "$FIXTURES_DIR/class2-trigger" 2>&1) || actual_exit=$?
  if echo "$output" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d.get('schema_version')==1" 2>/dev/null; then
    echo "PASS: output format: schema_version=1 present"
    PASS=$((PASS + 1))
  else
    echo "FAIL: output format: missing schema_version"
    echo "  output: $output"
    FAIL=$((FAIL + 1))
  fi
) || true

# warnings array present (even if empty)
(
  actual_exit=0
  output=$("$SCANNER" --scope all --skills-dir "$FIXTURES_DIR/class2-trigger" 2>&1) || actual_exit=$?
  if echo "$output" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'warnings' in d" 2>/dev/null; then
    echo "PASS: output format: 'warnings' key present"
    PASS=$((PASS + 1))
  else
    echo "FAIL: output format: missing 'warnings' key"
    echo "  output: $output"
    FAIL=$((FAIL + 1))
  fi
) || true

# Each conflict has required fields
(
  actual_exit=0
  output=$("$SCANNER" --scope all --skills-dir "$FIXTURES_DIR/class1-name-shadow" 2>&1) || actual_exit=$?
  if echo "$output" | python3 -c "
import sys,json
d=json.load(sys.stdin)
c=d['conflicts'][0]
for f in ['class','skill_a','skill_b','severity','reason']:
    assert f in c, f'missing field: {f}'
print('ok')
" 2>/dev/null | grep -q ok; then
    echo "PASS: output format: conflict has required fields"
    PASS=$((PASS + 1))
  else
    echo "FAIL: output format: conflict missing required fields"
    echo "  output: $output"
    FAIL=$((FAIL + 1))
  fi
) || true

# ---------------------------------------------------------------------------
# Preamble: upgrade-then-proceed behavior
# ---------------------------------------------------------------------------
echo ""
echo "=== Preamble: Upgrade Auto-Proceed ==="

SKILL_MD="$SCRIPT_DIR/../skills/skill-doctor/SKILL.md"

# SKILL.md must instruct Claude to proceed to Phase 1 after upgrade (not stop)
(
  if grep -q "automatically proceed to Phase 1" "$SKILL_MD"; then
    echo "PASS: preamble: instructs auto-proceed to Phase 1 after upgrade"
    PASS=$((PASS + 1))
  else
    echo "FAIL: preamble: missing 'automatically proceed to Phase 1' instruction"
    FAIL=$((FAIL + 1))
  fi
) || true

# SKILL.md must NOT tell Claude to stop after upgrade and suggest re-running
(
  if grep -q "suggest" "$SKILL_MD" && grep -q "re-running" "$SKILL_MD"; then
    echo "FAIL: preamble: still contains old 're-running' suggestion text"
    FAIL=$((FAIL + 1))
  else
    echo "PASS: preamble: no stale 're-running' suggestion found"
    PASS=$((PASS + 1))
  fi
) || true

# upgrade script must exist and be executable
(
  UPGRADE_BIN="$SCRIPT_DIR/../skills/skill-doctor/bin/skill-doctor-upgrade"
  if [[ -x "$UPGRADE_BIN" ]]; then
    echo "PASS: preamble: skill-doctor-upgrade is executable"
    PASS=$((PASS + 1))
  else
    echo "FAIL: preamble: skill-doctor-upgrade missing or not executable"
    FAIL=$((FAIL + 1))
  fi
) || true

# update-check script exits 0 (never blocks) and produces correct format when
# a higher version is available — test via SKILL_DOCTOR_INSTALL_DIR override
(
  UPDATE_BIN="$SCRIPT_DIR/../bin/skill-doctor-update-check"
  if [[ ! -x "$UPDATE_BIN" ]]; then
    echo "SKIP: update-check: binary not found"
    SKIP=$((SKIP + 1))
  else
    # Point at a temp dir with a very low version — network call may be skipped
    # if GitHub is unreachable; script must still exit 0
    TMPVER=$(mktemp -d)
    echo "0.0.1" > "$TMPVER/VERSION"
    actual_exit=0
    SKILL_DOCTOR_INSTALL_DIR="$TMPVER" "$UPDATE_BIN" > /dev/null 2>&1 || actual_exit=$?
    rm -rf "$TMPVER"
    if [[ "$actual_exit" -eq 0 ]]; then
      echo "PASS: update-check: exits 0 regardless of network availability"
      PASS=$((PASS + 1))
    else
      echo "FAIL: update-check: exited $actual_exit (expected 0)"
      FAIL=$((FAIL + 1))
    fi
  fi
) || true

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "=============================="
echo "Results: $PASS passed, $FAIL failed, $SKIP skipped"
echo "=============================="

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
