#!/bin/bash
# Copilot Chat Agent Notification Hook
# Sends notifications on Stop, PreToolUse (askQuestions/approval) events
# Channels: OS native, Telegram (configurable via COPILOT_NOTIFY_CHANNELS)
set -e

# --- Load .env file (fallback; shell env vars take priority) ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
if [ -f "$ENV_FILE" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    # Tolerate CRLF .env files and optional UTF-8 BOM
    line="${line%$'\r'}"
    # Skip comments and blank lines
    case "$line" in \#*|'') continue ;; esac
    # Ignore malformed lines without '='
    case "$line" in *=*) ;; *) continue ;; esac
    key="${line%%=*}"
    val="${line#*=}"
    key="${key#$'\ufeff'}"
    # Trim surrounding whitespace on key only
    key="${key#"${key%%[![:space:]]*}"}"
    key="${key%"${key##*[![:space:]]}"}"
    # Skip invalid env var names (prevents ${!key} errors)
    if ! [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      continue
    fi
    # Strip surrounding quotes
    val="${val#\"}"; val="${val%\"}"
    val="${val#\'}"; val="${val%\'}"
    # Only set if not already defined in shell environment
    if [ -z "${!key+x}" ]; then
      export "$key=$val"
    fi
  done < "$ENV_FILE"
fi

# --- Read stdin JSON ---
INPUT=$(cat)

# --- Parse JSON (jq with fallback) ---
parse_field() {
  local field="$1"
  if command -v jq &>/dev/null; then
    echo "$INPUT" | jq -r ".$field // empty" 2>/dev/null
  else
    # Fallback: grep/sed for simple field extraction
    echo "$INPUT" | grep -o "\"$field\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | sed "s/\"$field\"[[:space:]]*:[[:space:]]*\"//;s/\"$//" | head -1
  fi
}

parse_bool() {
  local field="$1"
  if command -v jq &>/dev/null; then
    echo "$INPUT" | jq -r ".$field // false" 2>/dev/null
  else
    echo "$INPUT" | grep -o "\"$field\"[[:space:]]*:[[:space:]]*[a-z]*" | sed "s/\"$field\"[[:space:]]*:[[:space:]]*//" | head -1
  fi
}

EVENT=$(parse_field "hook_event_name")
TOOL_NAME=$(parse_field "tool_name")
STOP_HOOK_ACTIVE=$(parse_bool "stop_hook_active")
TRANSCRIPT_PATH=$(parse_field "transcript_path")
SESSION_ID=$(parse_field "session_id")
CWD=$(parse_field "cwd")

# --- Detail level: short / normal / verbose ---
DETAIL_LEVEL=$(echo "${COPILOT_NOTIFY_DETAIL:-normal}" | tr '[:upper:]' '[:lower:]')

# --- Debug mode: log all tool_name values ---
if [ "${COPILOT_NOTIFY_DEBUG:-0}" = "1" ]; then
  echo "[DEBUG] hook_event_name=$EVENT tool_name=$TOOL_NAME stop_hook_active=$STOP_HOOK_ACTIVE" >&2
fi

# --- Event filter (COPILOT_NOTIFY_EVENTS) ---
NOTIFY_EVENTS="${COPILOT_NOTIFY_EVENTS:-all}"
NOTIFY_EVENTS_LOWER=$(echo "$NOTIFY_EVENTS" | tr '[:upper:]' '[:lower:]')
if [ "$NOTIFY_EVENTS_LOWER" = "none" ]; then
  echo '{"continue":true}'
  exit 0
fi
if [ "$NOTIFY_EVENTS_LOWER" != "all" ]; then
  EVENT_LOWER=$(echo "$EVENT" | tr '[:upper:]' '[:lower:]')
  MATCHED=false
  IFS=',' read -ra ALLOWED <<< "$NOTIFY_EVENTS_LOWER"
  for a in "${ALLOWED[@]}"; do
    if [ "$a" = "$EVENT_LOWER" ]; then
      MATCHED=true
      break
    fi
  done
  if [ "$MATCHED" = false ]; then
    echo '{"continue":true}'
    exit 0
  fi
fi

# --- Determine notification message ---
MSG=""

case "$EVENT" in
  Stop)
    # Prevent infinite loop
    if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
      echo '{"continue":true}'
      exit 0
    fi

    # Try to detect error from transcript (.jsonl — one JSON per line)
    if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
      HAS_ERROR=false
      PARSE_OK=false
      if command -v jq &>/dev/null; then
        # Read .jsonl line-by-line with jq
        if jq -e 'select(.type == "error" or (.type == "tool.execution_complete" and .error))' "$TRANSCRIPT_PATH" >/dev/null 2>&1; then
          HAS_ERROR=true
        fi
        PARSE_OK=true
      else
        # Fallback: grep for error patterns in .jsonl
        if grep -q '"type"[[:space:]]*:[[:space:]]*"error"' "$TRANSCRIPT_PATH" 2>/dev/null || \
           grep -q '"type"[[:space:]]*:[[:space:]]*"tool.execution_complete".*"error"' "$TRANSCRIPT_PATH" 2>/dev/null; then
          HAS_ERROR=true
        fi
        PARSE_OK=true
      fi
      if [ "$PARSE_OK" = true ]; then
        if [ "$HAS_ERROR" = true ]; then
          MSG="Copilot: 작업 실패!"
        else
          MSG="Copilot: 작업 완료!"
        fi
      else
        MSG="Copilot: 세션 종료"
      fi
    else
      # Fallback when transcript unavailable
      MSG="Copilot: 세션 종료"
    fi
    ;;

  PreToolUse)
    case "$TOOL_NAME" in
      *askQuestions*|*vscode_askQuestions*)
        MSG="Copilot: 질문을 기다리고 있어요!"
        ;;
      *)
        # No notification for other tools (prevent spam)
        echo '{"continue":true}'
        exit 0
        ;;
    esac
    ;;

  *)
    echo '{"continue":true}'
    exit 0
    ;;
esac

# --- Duplicate suppression (30s per eventType) ---
TEMP_DIR="${TMPDIR:-/tmp}"
LOCK_FILE="$TEMP_DIR/copilot_notify_last_${EVENT}"
NOW=$(date +%s)

if [ -f "$LOCK_FILE" ]; then
  LAST_SENT=$(cat "$LOCK_FILE" 2>/dev/null || echo "0")
  DIFF=$((NOW - LAST_SENT))
  if [ "$DIFF" -lt 30 ]; then
    echo '{"continue":true}'
    exit 0
  fi
fi
echo "$NOW" > "$LOCK_FILE"

# --- Enrich message with context (normal/verbose) ---
if [ "$DETAIL_LEVEL" != "short" ] && [ -n "$MSG" ] && [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  PROJECT_NAME=""
  FIRST_USER_MSG=""
  LAST_USER_MSG=""
  if [ -n "$CWD" ]; then
    PROJECT_NAME=$(basename "$CWD")
  fi
  if command -v jq &>/dev/null; then
    FIRST_USER_MSG=$(jq -r 'select(.type == "user.message") | .data.content // empty' "$TRANSCRIPT_PATH" 2>/dev/null | head -1 | tr '\n' ' ' | sed 's/[[:space:]]*$//')
    LAST_USER_MSG=$(jq -r 'select(.type == "user.message") | .data.content // empty' "$TRANSCRIPT_PATH" 2>/dev/null | tail -1 | tr '\n' ' ' | sed 's/[[:space:]]*$//')
  else
    FIRST_USER_MSG=$(grep '"user.message"' "$TRANSCRIPT_PATH" 2>/dev/null | head -1 | grep -o '"content"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/"content"[[:space:]]*:[[:space:]]*"//;s/"$//' | head -1)
    LAST_USER_MSG=$(grep '"user.message"' "$TRANSCRIPT_PATH" 2>/dev/null | tail -1 | grep -o '"content"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/"content"[[:space:]]*:[[:space:]]*"//;s/"$//' | head -1)
  fi
  CONTEXT=""

  # Try to get AI-generated session title from VS Code state DB (no external deps)
  CHAT_TITLE=""
  if [ -n "$TRANSCRIPT_PATH" ]; then
    STATE_DB="$(dirname "$(dirname "$(dirname "$TRANSCRIPT_PATH")")")/state.vscdb"
    if [ -f "$STATE_DB" ]; then
      # Extract title+lastMessageDate pairs from raw SQLite bytes using grep/awk
      CHAT_TITLE=$(grep -ao '"title"[[:space:]]*:[[:space:]]*"[^"]\{2,120\}"[[:space:]]*,[[:space:]]*"lastMessageDate"[[:space:]]*:[[:space:]]*[0-9]\+' "$STATE_DB" 2>/dev/null \
        | sed 's/.*"title"[[:space:]]*:[[:space:]]*"//;s/"[[:space:]]*,[[:space:]]*"lastMessageDate".*//' \
        | grep -v '^New Chat$' \
        | tail -1)
    fi
  fi

  if [ -n "$PROJECT_NAME" ]; then
    CONTEXT="${CONTEXT}"$'\n'"📂 ${PROJECT_NAME}"
  fi
  if [ -n "$CHAT_TITLE" ]; then
    TRUNC_TITLE=$(echo "$CHAT_TITLE" | cut -c1-40)
    [ ${#CHAT_TITLE} -gt 40 ] && TRUNC_TITLE="${TRUNC_TITLE}..."
    CONTEXT="${CONTEXT}"$'\n'"💬 ${TRUNC_TITLE}"
  elif [ -n "$FIRST_USER_MSG" ]; then
    TRUNC_FIRST=$(echo "$FIRST_USER_MSG" | cut -c1-30)
    [ ${#FIRST_USER_MSG} -gt 30 ] && TRUNC_FIRST="${TRUNC_FIRST}..."
    CONTEXT="${CONTEXT}"$'\n'"💬 \"${TRUNC_FIRST}\""
  fi
  if [ "$DETAIL_LEVEL" = "verbose" ]; then
    if [ -n "$SESSION_ID" ]; then
      SHORT_ID=$(echo "$SESSION_ID" | cut -c1-8)
      CONTEXT="${CONTEXT}"$'\n'"🏷 ${SHORT_ID}"
    fi
    if [ -n "$LAST_USER_MSG" ] && [ "$LAST_USER_MSG" != "$FIRST_USER_MSG" ]; then
      TRUNC_LAST=$(echo "$LAST_USER_MSG" | cut -c1-40)
      [ ${#LAST_USER_MSG} -gt 40 ] && TRUNC_LAST="${TRUNC_LAST}..."
      CONTEXT="${CONTEXT}"$'\n'"📝 \"${TRUNC_LAST}\""
    fi
  fi
  if [ -n "$CONTEXT" ]; then
    MSG="${MSG}${CONTEXT}"
  fi
fi

# --- Channel selection ---
CHANNELS="${COPILOT_NOTIFY_CHANNELS:-os}"

# --- Send: OS native notification ---
if echo "$CHANNELS" | grep -q "os"; then
  case "$(uname -s)" in
    Darwin)
      osascript -e "display notification \"$MSG\" with title \"GitHub Copilot\" sound name \"Glass\"" 2>/dev/null || true
      ;;
    Linux)
      notify-send "GitHub Copilot" "$MSG" 2>/dev/null || true
      ;;
  esac
fi

# --- Send: Telegram ---
if echo "$CHANNELS" | grep -q "telegram"; then
  if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
    curl --max-time 5 -s \
      -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
      -d "chat_id=${TELEGRAM_CHAT_ID}" \
      -d "text=${MSG}" \
      > /dev/null 2>&1 &
  else
    echo "[WARN] Telegram credentials not set (TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID)" >&2
  fi
fi

# --- Always output valid JSON for VS Code ---
echo '{"continue":true}'
exit 0
