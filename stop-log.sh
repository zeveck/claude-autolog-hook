#!/bin/bash
# Self-contained session logger. Runs in the Stop hook.
# Calls a Python script to convert JSONL transcript to readable markdown.
# Exits 0 always — Claude stops normally, no loop, no subagents.

export TZ="${TZ:-__TZ__}"

INPUT=$(cat)

TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // ""')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"')

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
  exit 0
fi

# Wait for transcript to finish flushing (file size stabilizes)
PREV_SIZE=-1
for _ in 1 2 3 4 5 6 7 8 9 10; do
  CURR_SIZE=$(wc -c < "$TRANSCRIPT_PATH" 2>/dev/null || echo 0)
  [ "$CURR_SIZE" = "$PREV_SIZE" ] && break
  PREV_SIZE=$CURR_SIZE
  sleep 0.2
done

# Extract start timestamp from first record that has one, convert to local time
START_TS=$(head -20 "$TRANSCRIPT_PATH" | jq -r 'select(.timestamp) | .timestamp' 2>/dev/null | head -1)
if [ -n "$START_TS" ]; then
  DATE=$(date -d "$START_TS" +%Y-%m-%d 2>/dev/null || date +%Y-%m-%d)
  TIME_PART=$(date -d "$START_TS" +%H%M 2>/dev/null || echo "0000")
  LOCAL_TS=$(date -d "$START_TS" --iso-8601=seconds 2>/dev/null || echo "$START_TS")
else
  DATE=$(date +%Y-%m-%d)
  TIME_PART="0000"
  LOCAL_TS=""
fi

mkdir -p .claude/logs

SCRIPT_DIR="$(dirname "$0")"
SHORT_ID=$(echo "$SESSION_ID" | cut -c1-8)
LOG_FILE=".claude/logs/${DATE}-${TIME_PART}-${SHORT_ID}.md"

python3 "${SCRIPT_DIR}/log-converter.py" \
  --transcript "$TRANSCRIPT_PATH" \
  --output "$LOG_FILE" \
  --session-id "$SESSION_ID" \
  --date "$DATE" \
  --start-time "$LOCAL_TS" \
  >/dev/null 2>> .claude/logs/.converter-errors.log

# Remove error log if empty — its presence is the signal
[ -f .claude/logs/.converter-errors.log ] && [ ! -s .claude/logs/.converter-errors.log ] \
  && rm .claude/logs/.converter-errors.log

exit 0
