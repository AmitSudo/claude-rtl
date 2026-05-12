#!/bin/bash
set -euo pipefail

# ============================================================
#  Claude RTL — Uninstaller
#
#  Removes the patched copy at ~/Applications/Claude-RTL.app.
#  Your original /Applications/Claude.app is never touched.
# ============================================================

PATCHED_APP="$HOME/Applications/Claude-RTL.app"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'

echo ""
echo -e "${BOLD}Claude RTL — Uninstaller${NC}"
echo ""

if [[ ! -d "$PATCHED_APP" ]]; then
  echo -e "  Nothing to uninstall — $PATCHED_APP does not exist."
  echo ""
  exit 0
fi

if pgrep -f "Claude-RTL.app" >/dev/null 2>&1; then
  echo -e "${RED}✖${NC} Claude-RTL.app is running. Quit it first."
  exit 1
fi

read -rp "Remove $PATCHED_APP? [Y/n] " ans
case "${ans:-Y}" in [Nn]*) echo "Aborted."; exit 0 ;; esac

rm -rf "$PATCHED_APP"

# Remove the parent directory if empty (~/Applications) — leave it otherwise
rmdir "$HOME/Applications" 2>/dev/null || true

echo -e "${GREEN}✔${NC} Removed $PATCHED_APP"
echo -e "${GREEN}✔${NC} Original /Applications/Claude.app was never touched."
echo ""
