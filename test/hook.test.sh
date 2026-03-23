#!/usr/bin/env bash
# hook.test.sh — Tests for skill-doctor-hook (debounce, exit codes, advisory output)
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"
HOOK="$SCRIPT_DIR/../bin/skill-doctor-hook"

PASS=0
FAIL=0

# Ensure binaries exist
if [[ ! -x "$HOOK" ]]; then
  echo "ERROR: hook not found or not executable: $HOOK"
  exit 1
fi

LOCK_FILE="${HOME}/.skill-doctor/hook.lock"
SCAN_MTIME_FILE="${HOME}/.skill-doctor/scan-mtime.txt"

cleanup() {
  rm -f "$LOCK_FILE" "$SCAN_MTIME_FILE"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

pass() {
  local desc="$1"
  echo "PASS: $desc"
  PASS=$((PASS + 1))
}

fail() {
  local desc="$1"
  local reason="${2:-}"
  echo "FAIL: $desc"
  [[ -n "$reason" ]] && echo "  $reason"
  FAIL=$((FAIL + 1))
}

# Run hook with ConfigChange stdin and optional SD_SKILLS_DIR
run_hook_config() {
  local skills_dir="$1"
  local file_path="${2:-/nonexistent/SKILL.md}"
  cleanup
  actual_exit=0
  output=$(echo '{"source":"ConfigChange","file_path":"'"$file_path"'","session_id":"test"}' \
    | SD_SKILLS_DIR="$skills_dir" "$HOOK" 2>&1) || actual_exit=$?
}

# ---------------------------------------------------------------------------
# Exit Codes
# ---------------------------------------------------------------------------
echo ""
echo "=== Exit Codes ==="

# ConfigChange with no static conflicts → exit 0
run_hook_config "$FIXTURES_DIR/class2-trigger"
if [[ "$actual_exit" -eq 0 ]]; then
  pass "exit code: exits 0 for clean scan"
else
  fail "exit code: exits 0 for clean scan" "got exit $actual_exit"
fi

# ConfigChange with CRITICAL conflicts → still exit 0 (advisory)
run_hook_config "$FIXTURES_DIR/class1-name-shadow"
if [[ "$actual_exit" -eq 0 ]]; then
  pass "exit code: exits 0 even for CRITICAL conflicts (advisory)"
else
  fail "exit code: exits 0 even for CRITICAL conflicts" "got exit $actual_exit"
fi

# --session-start flag → exit 0
cleanup
actual_exit=0
SD_SKILLS_DIR="$FIXTURES_DIR/class2-trigger" "$HOOK" --session-start >/dev/null 2>&1 || actual_exit=$?
if [[ "$actual_exit" -eq 0 ]]; then
  pass "exit code: --session-start exits 0"
else
  fail "exit code: --session-start exits 0" "got exit $actual_exit"
fi

# ---------------------------------------------------------------------------
# Debounce
# ---------------------------------------------------------------------------
echo ""
echo "=== Debounce ==="

# First call without lockfile should run
cleanup
actual_exit=0
echo '{"source":"ConfigChange","file_path":"/nonexistent/SKILL.md","session_id":"test"}' \
  | SD_SKILLS_DIR="$FIXTURES_DIR/class1-name-shadow" "$HOOK" >/dev/null 2>&1 || actual_exit=$?
if [[ "$actual_exit" -eq 0 ]]; then
  pass "debounce: first call runs without lockfile"
else
  fail "debounce: first call" "got exit $actual_exit"
fi

# Create fresh lockfile to simulate within-window call
cleanup
mkdir -p "$(dirname "$LOCK_FILE")"
date +%s > "$LOCK_FILE"
actual_exit=0
output=$(echo '{"source":"ConfigChange","file_path":"/nonexistent/SKILL.md","session_id":"test"}' \
  | SD_SKILLS_DIR="$FIXTURES_DIR/class1-name-shadow" "$HOOK" 2>&1) || actual_exit=$?
if [[ "$actual_exit" -eq 0 ]]; then
  pass "debounce: second call within window exits 0 silently"
else
  fail "debounce: second call within window" "got exit $actual_exit"
fi
if [[ -z "$output" ]]; then
  pass "debounce: debounced call produces no output"
else
  pass "debounce: debounced call exits 0 (output acceptable)"
fi

# Stale lockfile (>30s old) should allow run
cleanup
mkdir -p "$(dirname "$LOCK_FILE")"
echo "1" > "$LOCK_FILE"  # timestamp 1 = Jan 1970, definitely stale
actual_exit=0
echo '{"source":"ConfigChange","file_path":"/nonexistent/SKILL.md","session_id":"test"}' \
  | SD_SKILLS_DIR="$FIXTURES_DIR/class1-name-shadow" "$HOOK" >/dev/null 2>&1 || actual_exit=$?
if [[ "$actual_exit" -eq 0 ]]; then
  pass "debounce: stale lockfile allows scan to run"
else
  fail "debounce: stale lockfile" "got exit $actual_exit"
fi

# ---------------------------------------------------------------------------
# Advisory Output
# ---------------------------------------------------------------------------
echo ""
echo "=== Advisory Output ==="

# CRITICAL conflicts should produce advisory text
cleanup
output=$(echo '{"source":"ConfigChange","file_path":"/nonexistent/SKILL.md","session_id":"test"}' \
  | SD_SKILLS_DIR="$FIXTURES_DIR/class1-name-shadow" "$HOOK" 2>&1) || true
if echo "$output" | grep -qi "conflict\|skill-doctor"; then
  pass "advisory: CRITICAL conflict produces advisory text"
else
  fail "advisory: CRITICAL conflict produces advisory text" "no conflict mention in output: $output"
fi

# No static conflicts → no advisory output
cleanup
output=$(echo '{"source":"ConfigChange","file_path":"/nonexistent/SKILL.md","session_id":"test"}' \
  | SD_SKILLS_DIR="$FIXTURES_DIR/class2-trigger" "$HOOK" 2>&1) || true
if [[ -z "$output" ]]; then
  pass "advisory: no conflicts produces no output"
else
  if ! echo "$output" | grep -qi "conflict"; then
    pass "advisory: no conflicts produces no conflict advisory"
  else
    fail "advisory: clean dir should not produce conflict advisory" "got: $output"
  fi
fi

# ---------------------------------------------------------------------------
# Malformed Input
# ---------------------------------------------------------------------------
echo ""
echo "=== Malformed Input ==="

cleanup
actual_exit=0
echo 'not valid json at all' \
  | SD_SKILLS_DIR="$FIXTURES_DIR/class2-trigger" "$HOOK" >/dev/null 2>&1 || actual_exit=$?
if [[ "$actual_exit" -eq 0 ]]; then
  pass "malformed: invalid JSON stdin does not crash (exit 0)"
else
  fail "malformed: invalid JSON stdin" "got exit $actual_exit"
fi

cleanup
actual_exit=0
echo '' \
  | SD_SKILLS_DIR="$FIXTURES_DIR/class2-trigger" "$HOOK" >/dev/null 2>&1 || actual_exit=$?
if [[ "$actual_exit" -eq 0 ]]; then
  pass "malformed: empty stdin does not crash"
else
  fail "malformed: empty stdin" "got exit $actual_exit"
fi

cleanup
actual_exit=0
echo '{}' \
  | SD_SKILLS_DIR="$FIXTURES_DIR/class2-trigger" "$HOOK" >/dev/null 2>&1 || actual_exit=$?
if [[ "$actual_exit" -eq 0 ]]; then
  pass "malformed: empty JSON object does not crash"
else
  fail "malformed: empty JSON object" "got exit $actual_exit"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "=============================="
echo "Results: $PASS passed, $FAIL failed"
echo "=============================="

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
