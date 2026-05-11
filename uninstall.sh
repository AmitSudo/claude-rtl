#!/bin/bash
set -euo pipefail

# ============================================================
#  Claude Desktop — RTL Support Uninstaller
# ============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; BOLD='\033[1m'; NC='\033[0m'

echo ""
echo -e "${BOLD}Claude Desktop — RTL Support Uninstaller${NC}"
echo ""

if pgrep -f "Claude.app" > /dev/null 2>&1; then
  echo -e "${RED}✖ Claude Desktop is running. Please quit it first.${NC}"
  exit 1
fi

BACKUP=$(ls -dt ~/Claude.app.backup-* 2>/dev/null | head -1)

if [[ -z "$BACKUP" ]]; then
  echo -e "${RED}✖ No backup found. Cannot revert automatically.${NC}"
  echo "  You may need to reinstall Claude Desktop from https://claude.ai/download"
  exit 1
fi

echo "Found backup: $BACKUP"
read -rp "Restore Claude Desktop from this backup? [Y/n] " ans
case "$ans" in
  [Nn]*) echo "Aborted."; exit 0 ;;
esac

echo "Restoring..."
sudo rm -rf /Applications/Claude.app
sudo cp -R "$BACKUP" /Applications/Claude.app
sudo codesign --force --deep --sign - /Applications/Claude.app 2>/dev/null

if [[ -d "$HOME/.claude-rtl" ]]; then
  rm -rf "$HOME/.claude-rtl"
  echo -e "${GREEN}✔${NC} Removed ~/.claude-rtl"
fi

echo -e "${GREEN}✔${NC} Claude Desktop restored to original state."
echo ""
echo "You can now launch Claude Desktop."
echo "You may also delete your backups: rm -rf ~/Claude.app.backup-*"
echo ""
