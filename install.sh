#!/bin/bash
set -euo pipefail

# claude-session-logger installer
# Copies hook scripts and merges config into .claude/settings.json

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOKS_DIR=".claude/hooks"
SETTINGS_FILE=".claude/settings.json"

# --- Helpers ---

info()  { echo "  $1"; }
warn()  { echo "  [!] $1"; }
error() { echo "  [ERROR] $1" >&2; exit 1; }

prompt_yn() {
  # Usage: prompt_yn "Question?" [default y|n]
  local default="${2:-n}"
  local hint="[y/N]"
  [ "$default" = "y" ] && hint="[Y/n]"
  printf "  %s %s " "$1" "$hint"
  read -r answer
  answer="${answer:-$default}"
  [[ "$answer" =~ ^[Yy] ]]
}

# --- Preflight checks ---

echo ""
echo "claude-session-logger installer"
echo "================================"
echo ""

if [ ! -d ".git" ]; then
  error "Not in a git project root. Run this from your project directory."
fi

if ! command -v python3 &>/dev/null; then
  error "python3 is required but not found."
fi

if ! command -v jq &>/dev/null; then
  warn "jq not found. Settings will need manual configuration."
  HAS_JQ=false
else
  HAS_JQ=true
fi

# --- Timezone ---

echo "Timezone for log timestamps (e.g. America/New_York, America/Chicago, UTC)"
printf "  TZ [America/New_York]: "
read -r TZ_INPUT
TZ_VALUE="${TZ_INPUT:-America/New_York}"
echo ""

# --- Check for existing installation ---

if [ -f "$HOOKS_DIR/stop-log.sh" ]; then
  if ! prompt_yn "Hooks already installed. Overwrite?"; then
    echo ""
    info "Aborted."
    exit 0
  fi
  echo ""
fi

# --- Copy scripts ---

mkdir -p "$HOOKS_DIR"

for script in stop-log.sh subagent-stop-log.sh; do
  sed "s|__TZ__|$TZ_VALUE|g" "$SCRIPT_DIR/$script" > "$HOOKS_DIR/$script"
  chmod +x "$HOOKS_DIR/$script"
done

cp "$SCRIPT_DIR/log-converter.py" "$HOOKS_DIR/log-converter.py"

info "Installed scripts to $HOOKS_DIR/"

# --- Merge settings ---

HOOKS_CONFIG='{
  "Stop": [{"hooks": [{"type": "command", "command": ".claude/hooks/stop-log.sh"}]}],
  "SubagentStop": [{"hooks": [{"type": "command", "command": ".claude/hooks/subagent-stop-log.sh"}]}]
}'

if [ "$HAS_JQ" = true ]; then
  mkdir -p .claude

  if [ -f "$SETTINGS_FILE" ]; then
    # Merge hooks into existing settings
    EXISTING=$(cat "$SETTINGS_FILE")
    echo "$EXISTING" | jq --argjson hooks "$HOOKS_CONFIG" '.hooks = (.hooks // {}) * $hooks' > "$SETTINGS_FILE"
    info "Merged hook config into $SETTINGS_FILE"
  else
    # Create new settings file
    echo "$HOOKS_CONFIG" | jq '{hooks: .}' > "$SETTINGS_FILE"
    info "Created $SETTINGS_FILE"
  fi
else
  if [ -f "$SETTINGS_FILE" ]; then
    warn "Cannot auto-merge without jq. Add this to $SETTINGS_FILE manually:"
    echo ""
    echo '  "hooks": {'
    echo '    "Stop": [{"hooks": [{"type": "command", "command": ".claude/hooks/stop-log.sh"}]}],'
    echo '    "SubagentStop": [{"hooks": [{"type": "command", "command": ".claude/hooks/subagent-stop-log.sh"}]}]'
    echo '  }'
    echo ""
  else
    mkdir -p .claude
    cat > "$SETTINGS_FILE" <<'SETTINGS'
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": ".claude/hooks/stop-log.sh"
          }
        ]
      }
    ],
    "SubagentStop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": ".claude/hooks/subagent-stop-log.sh"
          }
        ]
      }
    ]
  }
}
SETTINGS
    info "Created $SETTINGS_FILE"
  fi
fi

# --- Done ---

echo ""
echo "Done! Session logs will appear in .claude/logs/ after each turn."
echo "Restart Claude Code to pick up the new hooks."
echo ""
