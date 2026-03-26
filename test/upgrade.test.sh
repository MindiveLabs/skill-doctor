#!/usr/bin/env bash
# upgrade.test.sh — Tests for the setup (install/upgrade) script and update-check binary
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SETUP="$REPO_ROOT/setup"
UPDATE_CHECK="$REPO_ROOT/skills/skill-doctor/bin/skill-doctor-update-check"

PASS=0
FAIL=0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; [[ -n "${2:-}" ]] && echo "  $2"; FAIL=$((FAIL + 1)); }

# Create a fresh temp install directory for each test group
INSTALL_DIR=$(mktemp -d)
cleanup() { rm -rf "$INSTALL_DIR"; }
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Prerequisites
# ---------------------------------------------------------------------------

if [[ ! -x "$SETUP" ]]; then
  echo "ERROR: setup not found or not executable: $SETUP"
  exit 1
fi

if [[ ! -x "$UPDATE_CHECK" ]]; then
  echo "ERROR: update-check not found or not executable: $UPDATE_CHECK"
  exit 1
fi

# ---------------------------------------------------------------------------
# Initial Install
# ---------------------------------------------------------------------------
echo ""
echo "=== Initial Install ==="

actual_exit=0
SKILL_DOCTOR_INSTALL_DIR="$INSTALL_DIR" "$SETUP" >/dev/null 2>&1 || actual_exit=$?
if [[ "$actual_exit" -eq 0 ]]; then
  pass "install: setup exits 0"
else
  fail "install: setup exits 0" "got exit $actual_exit"
fi

# Verify all expected files are present
for f in SKILL.md VERSION bin/skill-doctor-scan bin/skill-doctor-hook bin/skill-doctor-update-check; do
  if [[ -f "$INSTALL_DIR/$f" ]]; then
    pass "install: $f was copied"
  else
    fail "install: $f was copied" "file not found: $INSTALL_DIR/$f"
  fi
done

# Verify binaries are executable
for b in bin/skill-doctor-scan bin/skill-doctor-hook bin/skill-doctor-update-check; do
  if [[ -x "$INSTALL_DIR/$b" ]]; then
    pass "install: $b is executable"
  else
    fail "install: $b is executable" "$INSTALL_DIR/$b is not executable"
  fi
done

# Verify installed VERSION matches source VERSION
SOURCE_VERSION=$(cat "$REPO_ROOT/skills/skill-doctor/VERSION" 2>/dev/null | tr -d '[:space:]')
INSTALLED_VERSION=$(cat "$INSTALL_DIR/VERSION" 2>/dev/null | tr -d '[:space:]')
if [[ "$SOURCE_VERSION" == "$INSTALLED_VERSION" ]]; then
  pass "install: installed VERSION matches source ($SOURCE_VERSION)"
else
  fail "install: installed VERSION matches source" "source=$SOURCE_VERSION installed=$INSTALLED_VERSION"
fi

# Verify installed SKILL.md matches source SKILL.md
if diff -q "$REPO_ROOT/skills/skill-doctor/SKILL.md" "$INSTALL_DIR/SKILL.md" >/dev/null 2>&1; then
  pass "install: installed SKILL.md matches source"
else
  fail "install: installed SKILL.md matches source" "files differ"
fi

# ---------------------------------------------------------------------------
# Upgrade (simulated version bump)
# ---------------------------------------------------------------------------
echo ""
echo "=== Upgrade (simulated version bump) ==="

# Write a fake old VERSION to the install dir to simulate prior install
echo "0.0.1" > "$INSTALL_DIR/VERSION"
# Also write a marker string into the installed SKILL.md to confirm overwrite
echo "# old content" >> "$INSTALL_DIR/SKILL.md"

# Run setup again (idempotent upgrade)
actual_exit=0
SKILL_DOCTOR_INSTALL_DIR="$INSTALL_DIR" "$SETUP" >/dev/null 2>&1 || actual_exit=$?
if [[ "$actual_exit" -eq 0 ]]; then
  pass "upgrade: re-running setup exits 0"
else
  fail "upgrade: re-running setup exits 0" "got exit $actual_exit"
fi

# Verify VERSION was updated to current source
UPGRADED_VERSION=$(cat "$INSTALL_DIR/VERSION" 2>/dev/null | tr -d '[:space:]')
if [[ "$SOURCE_VERSION" == "$UPGRADED_VERSION" ]]; then
  pass "upgrade: VERSION updated to $SOURCE_VERSION"
else
  fail "upgrade: VERSION updated" "expected=$SOURCE_VERSION got=$UPGRADED_VERSION"
fi

# Verify SKILL.md was overwritten (old marker should be gone)
if diff -q "$REPO_ROOT/skills/skill-doctor/SKILL.md" "$INSTALL_DIR/SKILL.md" >/dev/null 2>&1; then
  pass "upgrade: SKILL.md overwritten with current source"
else
  fail "upgrade: SKILL.md overwritten with current source" "files differ after upgrade"
fi

# Verify scanner binary was updated (still executable after overwrite)
if [[ -x "$INSTALL_DIR/bin/skill-doctor-scan" ]]; then
  pass "upgrade: scanner binary still executable after upgrade"
else
  fail "upgrade: scanner binary still executable after upgrade"
fi

# ---------------------------------------------------------------------------
# Idempotency (setup is safe to re-run multiple times)
# ---------------------------------------------------------------------------
echo ""
echo "=== Idempotency ==="

for i in 1 2 3; do
  actual_exit=0
  SKILL_DOCTOR_INSTALL_DIR="$INSTALL_DIR" "$SETUP" >/dev/null 2>&1 || actual_exit=$?
  if [[ "$actual_exit" -eq 0 ]]; then
    pass "idempotency: run $i exits 0"
  else
    fail "idempotency: run $i exits 0" "got exit $actual_exit"
  fi
done

FINAL_VERSION=$(cat "$INSTALL_DIR/VERSION" 2>/dev/null | tr -d '[:space:]')
if [[ "$SOURCE_VERSION" == "$FINAL_VERSION" ]]; then
  pass "idempotency: VERSION unchanged after 3 re-runs ($SOURCE_VERSION)"
else
  fail "idempotency: VERSION unchanged after 3 re-runs" "expected=$SOURCE_VERSION got=$FINAL_VERSION"
fi

# ---------------------------------------------------------------------------
# update-check: graceful failures
# ---------------------------------------------------------------------------
echo ""
echo "=== Update Check ==="

# Exits 0 when VERSION file is missing
TMP_DIR=$(mktemp -d)
actual_exit=0
SKILL_DOCTOR_INSTALL_DIR="$TMP_DIR" "$UPDATE_CHECK" >/dev/null 2>&1 || actual_exit=$?
if [[ "$actual_exit" -eq 0 ]]; then
  pass "update-check: exits 0 when VERSION file missing"
else
  fail "update-check: exits 0 when VERSION file missing" "got exit $actual_exit"
fi
rm -rf "$TMP_DIR"

# Exits 0 on network failure (unreachable host)
TMP_DIR=$(mktemp -d)
echo "0.1.0" > "$TMP_DIR/VERSION"
actual_exit=0
output=$(SKILL_DOCTOR_INSTALL_DIR="$TMP_DIR" GITHUB_REPO="github.invalid/no-such-repo" "$UPDATE_CHECK" 2>/dev/null) || actual_exit=$?
if [[ "$actual_exit" -eq 0 ]]; then
  pass "update-check: exits 0 on network failure"
else
  fail "update-check: exits 0 on network failure" "got exit $actual_exit"
fi
if [[ -z "$output" ]]; then
  pass "update-check: no output on network failure"
else
  fail "update-check: no output on network failure" "got: $output"
fi
rm -rf "$TMP_DIR"

# Outputs UPGRADE_AVAILABLE when a newer version is available (mocked)
# Simulate by writing an old VERSION and overriding the binary to return a fake latest tag
TMP_DIR=$(mktemp -d)
echo "0.0.1" > "$TMP_DIR/VERSION"
# Create a wrapper that mocks the curl call
MOCK_BIN_DIR=$(mktemp -d)
cat > "$MOCK_BIN_DIR/curl" <<'MOCK'
#!/usr/bin/env bash
# Mock curl: return a fake GitHub releases response with version 9.9.9
echo '{"tag_name": "v9.9.9", "name": "9.9.9"}'
MOCK
chmod +x "$MOCK_BIN_DIR/curl"
actual_exit=0
output=$(PATH="$MOCK_BIN_DIR:$PATH" SKILL_DOCTOR_INSTALL_DIR="$TMP_DIR" "$UPDATE_CHECK" 2>/dev/null) || actual_exit=$?
if [[ "$actual_exit" -eq 0 ]]; then
  pass "update-check: exits 0 when upgrade available"
else
  fail "update-check: exits 0 when upgrade available" "got exit $actual_exit"
fi
if echo "$output" | grep -q "UPGRADE_AVAILABLE 0.0.1 9.9.9"; then
  pass "update-check: outputs UPGRADE_AVAILABLE <current> <latest>"
else
  fail "update-check: outputs UPGRADE_AVAILABLE <current> <latest>" "got: '$output'"
fi
rm -rf "$TMP_DIR" "$MOCK_BIN_DIR"

# No output when already on latest version
TMP_DIR=$(mktemp -d)
echo "9.9.9" > "$TMP_DIR/VERSION"
MOCK_BIN_DIR=$(mktemp -d)
cat > "$MOCK_BIN_DIR/curl" <<'MOCK'
#!/usr/bin/env bash
echo '{"tag_name": "v9.9.9"}'
MOCK
chmod +x "$MOCK_BIN_DIR/curl"
actual_exit=0
output=$(PATH="$MOCK_BIN_DIR:$PATH" SKILL_DOCTOR_INSTALL_DIR="$TMP_DIR" "$UPDATE_CHECK" 2>/dev/null) || actual_exit=$?
if [[ "$actual_exit" -eq 0 ]]; then
  pass "update-check: exits 0 when already on latest"
else
  fail "update-check: exits 0 when already on latest" "got exit $actual_exit"
fi
if [[ -z "$output" ]]; then
  pass "update-check: no output when already on latest"
else
  fail "update-check: no output when already on latest" "got: '$output'"
fi
rm -rf "$TMP_DIR" "$MOCK_BIN_DIR"

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
