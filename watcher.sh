#!/bin/bash
# Claude RTL — Auto-reapply watcher
# Monitors app.asar for changes (e.g. after Claude Desktop auto-updates)
# and re-applies the RTL patch automatically.

set -euo pipefail

ASAR="/Applications/Claude.app/Contents/Resources/app.asar"
INSTALL_DIR="$HOME/.claude-rtl"
LOG="$INSTALL_DIR/watcher.log"
MARKER="RTL injection hook"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG"; }

check_and_patch() {
  # Extract and check if patch is present
  local tmp=$(mktemp -d)
  npx --yes @electron/asar extract "$ASAR" "$tmp/check" 2>/dev/null || { rm -rf "$tmp"; return; }
  local main=$(python3 -c "import json; print(json.load(open('$tmp/check/package.json'))['main'])")

  if grep -q "$MARKER" "$tmp/check/$main" 2>/dev/null; then
    rm -rf "$tmp"
    return
  fi
  rm -rf "$tmp"

  log "Update detected — patch missing. Waiting for Claude to finish updating..."
  sleep 10

  # Wait for Claude to stop (it may restart after update)
  local waited=0
  while pgrep -f "Claude.app" > /dev/null 2>&1 && [[ $waited -lt 120 ]]; do
    sleep 5
    waited=$((waited + 5))
  done

  if pgrep -f "Claude.app" > /dev/null 2>&1; then
    log "Claude still running after 2min — skipping auto-patch"
    return
  fi

  log "Re-applying RTL patch..."
  if bash "$INSTALL_DIR/reapply.sh" >> "$LOG" 2>&1; then
    log "Patch re-applied successfully"
  else
    log "ERROR: Patch failed — run manually: bash ~/.claude-rtl/reapply.sh"
  fi
}

log "Watcher started"

# Initial check
[[ -f "$ASAR" ]] && check_and_patch

# Watch for changes using fswatch if available, otherwise poll
if command -v fswatch &>/dev/null; then
  fswatch -1 -l 5 --event Updated "$ASAR" 2>/dev/null | while read -r _; do
    sleep 3
    check_and_patch
  done
else
  # Polling fallback (check every 60s)
  LAST_MOD=$(stat -f %m "$ASAR" 2>/dev/null || echo "0")
  while true; do
    sleep 60
    CUR_MOD=$(stat -f %m "$ASAR" 2>/dev/null || echo "0")
    if [[ "$CUR_MOD" != "$LAST_MOD" ]]; then
      LAST_MOD="$CUR_MOD"
      check_and_patch
    fi
  done
fi
