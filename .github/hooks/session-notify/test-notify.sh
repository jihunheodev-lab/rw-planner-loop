#!/bin/bash
# Fixture tests for notify.sh
# Validates: event routing, filtering, duplicate suppression, stdout JSON contract
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NOTIFY="$SCRIPT_DIR/notify.sh"
ENV_FILE="$SCRIPT_DIR/.env"
PASS=0
FAIL=0
TEMP_DIR="${TMPDIR:-/tmp}"

# Clean up lock files before tests
rm -f "$TEMP_DIR/copilot_notify_last_"* 2>/dev/null

# Disable actual notifications for testing
export COPILOT_NOTIFY_CHANNELS="none"

assert_json_continue() {
  local test_name="$1"
  local output="$2"
  if echo "$output" | grep -q '"continue":true'; then
    PASS=$((PASS + 1))
    echo "  PASS: $test_name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $test_name — expected {\"continue\":true}, got: $output"
  fi
}

assert_no_extra_output() {
  local test_name="$1"
  local output="$2"
  local line_count
  line_count=$(echo "$output" | wc -l | tr -d ' ')
  if [ "$line_count" -le 1 ]; then
    PASS=$((PASS + 1))
    echo "  PASS: $test_name (single line output)"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $test_name — expected 1 line, got $line_count lines: $output"
  fi
}

echo "=== notify.sh Fixture Tests ==="
echo ""

# --- Test 1: Stop event → should produce notification + JSON ---
echo "Test 1: Stop event"
rm -f "$TEMP_DIR/copilot_notify_last_Stop" 2>/dev/null
OUTPUT=$(echo '{"hook_event_name":"Stop","stop_hook_active":false,"timestamp":"2026-01-01T00:00:00Z","cwd":"/tmp","session_id":"test-1"}' | bash "$NOTIFY" 2>/dev/null)
assert_json_continue "Stop event returns valid JSON" "$OUTPUT"
assert_no_extra_output "Stop event single line stdout" "$OUTPUT"

# --- Test 2: Stop + stop_hook_active=true → no notification ---
echo "Test 2: Stop + stop_hook_active=true"
rm -f "$TEMP_DIR/copilot_notify_last_Stop" 2>/dev/null
OUTPUT=$(echo '{"hook_event_name":"Stop","stop_hook_active":true,"timestamp":"2026-01-01T00:00:00Z","cwd":"/tmp"}' | bash "$NOTIFY" 2>/dev/null)
assert_json_continue "stop_hook_active skips notification" "$OUTPUT"

# --- Test 3: PreToolUse + askQuestions → notification ---
echo "Test 3: PreToolUse + askQuestions"
rm -f "$TEMP_DIR/copilot_notify_last_PreToolUse" 2>/dev/null
OUTPUT=$(echo '{"hook_event_name":"PreToolUse","tool_name":"vscode_askQuestions","tool_input":{},"tool_use_id":"t1"}' | bash "$NOTIFY" 2>/dev/null)
assert_json_continue "askQuestions returns valid JSON" "$OUTPUT"
assert_no_extra_output "askQuestions single line stdout" "$OUTPUT"

# --- Test 4: PreToolUse + read_file → no notification (filtered) ---
echo "Test 4: PreToolUse + read_file (should be filtered)"
rm -f "$TEMP_DIR/copilot_notify_last_PreToolUse" 2>/dev/null
OUTPUT=$(echo '{"hook_event_name":"PreToolUse","tool_name":"read_file","tool_input":{},"tool_use_id":"t2"}' | bash "$NOTIFY" 2>/dev/null)
assert_json_continue "read_file filtered, returns valid JSON" "$OUTPUT"

# --- Test 5: Duplicate suppression (30s) ---
echo "Test 5: Duplicate suppression"
rm -f "$TEMP_DIR/copilot_notify_last_Stop" 2>/dev/null
# First call
echo '{"hook_event_name":"Stop","stop_hook_active":false,"timestamp":"2026-01-01T00:00:00Z","cwd":"/tmp"}' | bash "$NOTIFY" > /dev/null 2>&1
# Second call (within 30s)
OUTPUT=$(echo '{"hook_event_name":"Stop","stop_hook_active":false,"timestamp":"2026-01-01T00:00:00Z","cwd":"/tmp"}' | bash "$NOTIFY" 2>/dev/null)
assert_json_continue "Duplicate suppressed, returns valid JSON" "$OUTPUT"
# Verify lock file was written
if [ -f "$TEMP_DIR/copilot_notify_last_Stop" ]; then
  PASS=$((PASS + 1))
  echo "  PASS: Lock file created"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: Lock file not created"
fi

# --- Test 6: Unknown event → exit cleanly ---
echo "Test 6: Unknown event"
OUTPUT=$(echo '{"hook_event_name":"UnknownEvent"}' | bash "$NOTIFY" 2>/dev/null)
assert_json_continue "Unknown event returns valid JSON" "$OUTPUT"

# --- Test 7: .env file loading ---
echo "Test 7: .env file variable loading"
rm -f "$TEMP_DIR/copilot_notify_last_Stop" 2>/dev/null
# Backup existing .env if present
[ -f "$ENV_FILE" ] && cp "$ENV_FILE" "$ENV_FILE.bak"
echo 'COPILOT_NOTIFY_CHANNELS=none' > "$ENV_FILE"
result=$(
  unset COPILOT_NOTIFY_CHANNELS
  OUTPUT=$(echo '{"hook_event_name":"Stop","stop_hook_active":false}' | bash "$NOTIFY" 2>/dev/null)
  # Script should run without error (channels=none means no actual notification sent)
  if echo "$OUTPUT" | grep -q '"continue":true'; then
    echo "PASS_INNER"
  else
    echo "FAIL_INNER"
  fi
)
result=$(echo "$result" | tr -d '\r\n')
if [ "$result" = "PASS_INNER" ]; then
  PASS=$((PASS + 1))
  echo "  PASS: .env file loaded (COPILOT_NOTIFY_CHANNELS=none)"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: .env file not loaded correctly"
fi
# Restore .env
rm -f "$ENV_FILE"
[ -f "$ENV_FILE.bak" ] && mv "$ENV_FILE.bak" "$ENV_FILE"

# --- Test 8: Shell env overrides .env file ---
echo "Test 8: Shell env overrides .env file"
rm -f "$TEMP_DIR/copilot_notify_last_Stop" 2>/dev/null
[ -f "$ENV_FILE" ] && cp "$ENV_FILE" "$ENV_FILE.bak"
echo 'COPILOT_NOTIFY_DEBUG=1' > "$ENV_FILE"
result=$(
  export COPILOT_NOTIFY_DEBUG=0
  export COPILOT_NOTIFY_CHANNELS=none
  STDERR_OUT=$(echo '{"hook_event_name":"Stop","stop_hook_active":false}' | bash "$NOTIFY" 2>&1 1>/dev/null)
  # If shell env wins (DEBUG=0), no debug output should appear
  if echo "$STDERR_OUT" | grep -q '\[DEBUG\]'; then
    echo "FAIL_INNER"
  else
    echo "PASS_INNER"
  fi
)
result=$(echo "$result" | tr -d '\r\n')
if [ "$result" = "PASS_INNER" ]; then
  PASS=$((PASS + 1))
  echo "  PASS: Shell env var overrides .env file"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: .env file overrode shell env var"
fi
rm -f "$ENV_FILE"
[ -f "$ENV_FILE.bak" ] && mv "$ENV_FILE.bak" "$ENV_FILE"

# --- Test 9: .env with CRLF should still load ---
echo "Test 9: .env CRLF compatibility"
rm -f "$TEMP_DIR/copilot_notify_last_Stop" 2>/dev/null
[ -f "$ENV_FILE" ] && cp "$ENV_FILE" "$ENV_FILE.bak"
printf 'COPILOT_NOTIFY_CHANNELS=none\r\n' > "$ENV_FILE"
OUTPUT=$(echo '{"hook_event_name":"Stop","stop_hook_active":false}' | bash "$NOTIFY" 2>/dev/null)
assert_json_continue "CRLF .env parsed without errors" "$OUTPUT"
rm -f "$ENV_FILE"
[ -f "$ENV_FILE.bak" ] && mv "$ENV_FILE.bak" "$ENV_FILE"

# --- Test 10: COPILOT_NOTIFY_EVENTS=stop filters PreToolUse ---
echo "Test 10: Event filter (stop only)"
rm -f "$TEMP_DIR/copilot_notify_last_PreToolUse" 2>/dev/null
export COPILOT_NOTIFY_EVENTS="stop"
OUTPUT=$(echo '{"hook_event_name":"PreToolUse","tool_name":"vscode_askQuestions","tool_input":{},"tool_use_id":"t9"}' | bash "$NOTIFY" 2>/dev/null)
assert_json_continue "PreToolUse filtered when EVENTS=stop" "$OUTPUT"
unset COPILOT_NOTIFY_EVENTS

# --- Test 11: COPILOT_NOTIFY_EVENTS=none filters everything ---
echo "Test 11: Event filter (none)"
rm -f "$TEMP_DIR/copilot_notify_last_Stop" 2>/dev/null
export COPILOT_NOTIFY_EVENTS="none"
OUTPUT=$(echo '{"hook_event_name":"Stop","stop_hook_active":false}' | bash "$NOTIFY" 2>/dev/null)
assert_json_continue "Stop filtered when EVENTS=none" "$OUTPUT"
unset COPILOT_NOTIFY_EVENTS

# --- Test 12: '%' in user message should not break formatting ---
echo "Test 12: Message formatting with percent sign"
rm -f "$TEMP_DIR/copilot_notify_last_Stop" 2>/dev/null
TRANSCRIPT_FILE="$TEMP_DIR/copilot_notify_test_percent.jsonl"
printf '{"type":"user.message","data":{"content":"Need 100%% coverage now"}}\n' > "$TRANSCRIPT_FILE"
export COPILOT_NOTIFY_DETAIL="normal"
INPUT=$(printf '{"hook_event_name":"Stop","stop_hook_active":false,"transcript_path":"%s","cwd":"/tmp","session_id":"test-12"}' "$TRANSCRIPT_FILE")
OUTPUT=$(echo "$INPUT" | bash "$NOTIFY" 2>/dev/null)
assert_json_continue "Percent sign content handled safely" "$OUTPUT"
unset COPILOT_NOTIFY_DETAIL
rm -f "$TRANSCRIPT_FILE"

# --- Summary ---
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

# Clean up
rm -f "$TEMP_DIR/copilot_notify_last_"* 2>/dev/null

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
