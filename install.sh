#!/bin/bash
set -euo pipefail

# ============================================================
#  Claude Desktop — RTL Support Installer (macOS)
#  Adds right-to-left text rendering for Hebrew, Arabic, etc.
#
#  RTL JS logic by shraga100: https://github.com/shraga100/claude-desktop-rtl-patch
#  macOS approach inspired by toboly: https://github.com/toboly/claude-desktop-rtl-patch-mac
# ============================================================

APP="/Applications/Claude.app"
ASAR="$APP/Contents/Resources/app.asar"
INSTALL_DIR="$HOME/.claude-rtl"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Colors & helpers ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

step_n=0
step() { step_n=$((step_n+1)); echo -e "\n${BLUE}${BOLD}[$step_n/$total_steps]${NC} $1"; }
ok()   { echo -e "  ${GREEN}✔${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }
fail() { echo -e "  ${RED}✖ $1${NC}"; exit 1; }

ask_yes() {
  read -rp "  → $1 [Y/n] " ans
  case "$ans" in
    [Nn]*) return 1 ;;
    *) return 0 ;;
  esac
}

total_steps=7

# --- Banner ---
echo ""
echo -e "${BOLD}┌─────────────────────────────────────────────┐${NC}"
echo -e "${BOLD}│  Claude Desktop — RTL Support Installer     │${NC}"
echo -e "${BOLD}│  Hebrew · Arabic · Persian · Urdu            │${NC}"
echo -e "${BOLD}└─────────────────────────────────────────────┘${NC}"
echo ""

# --- Step 1: Preflight checks ---
step "Preflight checks"

if [[ "$(uname)" != "Darwin" ]]; then
  fail "This script only works on macOS."
fi
ok "Running on macOS"

if [[ ! -d "$APP" ]]; then
  fail "Claude Desktop not found at $APP"
fi
ok "Claude Desktop found"

VERSION=$(defaults read "$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "unknown")
ok "Version: $VERSION"

if pgrep -f "Claude.app" > /dev/null 2>&1; then
  warn "Claude Desktop is running."
  if ask_yes "Quit Claude Desktop now?"; then
    pkill -f "Claude.app" 2>/dev/null || true
    sleep 2
    if pgrep -f "Claude.app" > /dev/null 2>&1; then
      pkill -9 -f "Claude.app" 2>/dev/null || true
      sleep 1
    fi
    ok "Claude Desktop stopped"
  else
    fail "Please quit Claude Desktop and run this script again."
  fi
fi
ok "Claude Desktop is not running"

if ! command -v npx &>/dev/null; then
  fail "npx not found. Please install Node.js first: https://nodejs.org"
fi
ok "npx available"

# --- Step 2: Backup ---
step "Creating backup"

BACKUP_PATH="$HOME/Claude.app.backup-$(date +%Y%m%d-%H%M%S)"
echo -e "  Backup location: ${BOLD}$BACKUP_PATH${NC}"

if ask_yes "Create backup?"; then
  sudo cp -R "$APP" "$BACKUP_PATH"
  ok "Backup created"
else
  warn "Skipping backup (not recommended)"
fi

# --- Step 3: Extract ---
step "Extracting app.asar"

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

npx --yes @electron/asar extract "$ASAR" "$WORK_DIR/claude-asar" 2>/dev/null
ok "Extracted to temp directory"

# --- Step 4: Find and patch ---
step "Applying RTL patch"

MAIN=$(python3 -c "import json; print(json.load(open('$WORK_DIR/claude-asar/package.json'))['main'])")
MAIN_FILE="$WORK_DIR/claude-asar/$MAIN"
MAIN_DIR=$(dirname "$MAIN_FILE")

if [[ ! -f "$MAIN_FILE" ]]; then
  fail "Main entry file not found: $MAIN"
fi
ok "Main entry: $MAIN"

# Copy rtl.js into the asar
RTL_JS_SRC="$SCRIPT_DIR/rtl.js"
if [[ ! -f "$RTL_JS_SRC" ]]; then
  fail "rtl.js not found in script directory: $SCRIPT_DIR"
fi
cp "$RTL_JS_SRC" "$MAIN_DIR/rtl.js"
ok "Copied rtl.js into asar"

# Remove old patch if present, then append new hook
if grep -q "RTL injection hook" "$MAIN_FILE"; then
  python3 -c "
import re
with open('$MAIN_FILE', 'r') as f:
    content = f.read()
content = re.sub(r'\n// --- RTL injection hook.*', '', content, flags=re.DOTALL)
with open('$MAIN_FILE', 'w') as f:
    f.write(content)
"
  ok "Removed old RTL patch"
fi

cat >> "$MAIN_FILE" << 'HOOK'

// --- RTL injection hook ---
try {
  const { app: __rtlApp } = require('electron');
  const __rtlCode = require('fs').readFileSync(require('path').join(__dirname, 'rtl.js'), 'utf8');
  __rtlApp.on('web-contents-created', (_e, contents) => {
    contents.on('did-finish-load', () => {
      contents.executeJavaScript(__rtlCode).catch(() => {});
    });
  });
} catch (_e) {}
// --- end RTL injection hook ---
HOOK
ok "RTL hook added to main entry"

# --- Step 5: Repack ---
step "Repacking app.asar"

sudo npx --yes @electron/asar pack "$WORK_DIR/claude-asar" "$ASAR" 2>/dev/null
ok "app.asar repacked"

# --- Step 6: Disable asar integrity fuse & re-sign ---
step "Disabling asar integrity check & re-signing"

sudo npx --yes @electron/fuses write --app "$APP" EnableEmbeddedAsarIntegrityValidation=off 2>/dev/null
ok "Asar integrity fuse disabled"

sudo codesign --force --deep --sign - "$APP" 2>/dev/null
ok "App re-signed (ad-hoc)"

if codesign --verify --verbose "$APP" 2>&1 | grep -q "valid on disk"; then
  ok "Signature verified"
else
  warn "Signature verification returned unexpected result — app may still work"
fi

# --- Step 7: Install helper scripts ---
step "Installing helper scripts"

mkdir -p "$INSTALL_DIR"
cp "$RTL_JS_SRC" "$INSTALL_DIR/rtl.js"

cat > "$INSTALL_DIR/reapply.sh" << 'REAPPLY_SCRIPT'
#!/bin/bash
set -euo pipefail
APP="/Applications/Claude.app"
ASAR="$APP/Contents/Resources/app.asar"
INSTALL_DIR="$HOME/.claude-rtl"

if pgrep -f "Claude.app" > /dev/null 2>&1; then
  echo "ERROR: Claude Desktop is running. Please quit it first."; exit 1
fi
if [[ ! -d "$APP" ]]; then
  echo "ERROR: Claude Desktop not found."; exit 1
fi
if [[ ! -f "$INSTALL_DIR/rtl.js" ]]; then
  echo "ERROR: rtl.js not found in $INSTALL_DIR"; exit 1
fi

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

echo "Extracting app.asar..."
npx --yes @electron/asar extract "$ASAR" "$WORK_DIR/claude-asar" 2>/dev/null

MAIN=$(python3 -c "import json; print(json.load(open('$WORK_DIR/claude-asar/package.json'))['main'])")
MAIN_FILE="$WORK_DIR/claude-asar/$MAIN"
MAIN_DIR=$(dirname "$MAIN_FILE")

if [[ ! -f "$MAIN_FILE" ]]; then
  echo "ERROR: Main entry file not found: $MAIN"; exit 1
fi

# Copy rtl.js
cp "$INSTALL_DIR/rtl.js" "$MAIN_DIR/rtl.js"

# Remove old patch if present
if grep -q "RTL injection hook" "$MAIN_FILE"; then
  python3 -c "
import re
with open('$MAIN_FILE', 'r') as f:
    content = f.read()
content = re.sub(r'\n// --- RTL injection hook.*', '', content, flags=re.DOTALL)
with open('$MAIN_FILE', 'w') as f:
    f.write(content)
"
fi

# Append hook
cat >> "$MAIN_FILE" << 'HOOK'

// --- RTL injection hook ---
try {
  const { app: __rtlApp } = require('electron');
  const __rtlCode = require('fs').readFileSync(require('path').join(__dirname, 'rtl.js'), 'utf8');
  __rtlApp.on('web-contents-created', (_e, contents) => {
    contents.on('did-finish-load', () => {
      contents.executeJavaScript(__rtlCode).catch(() => {});
    });
  });
} catch (_e) {}
// --- end RTL injection hook ---
HOOK

echo "Repacking app.asar..."
sudo npx --yes @electron/asar pack "$WORK_DIR/claude-asar" "$ASAR" 2>/dev/null

echo "Disabling asar integrity fuse..."
sudo npx --yes @electron/fuses write --app "$APP" EnableEmbeddedAsarIntegrityValidation=off 2>/dev/null

echo "Re-signing..."
sudo codesign --force --deep --sign - "$APP" 2>/dev/null
codesign --verify --verbose "$APP" 2>&1

echo "Done! RTL patch applied. You can now launch Claude Desktop."
REAPPLY_SCRIPT

cat > "$INSTALL_DIR/revert.sh" << 'REVERT_SCRIPT'
#!/bin/bash
set -euo pipefail

if pgrep -f "Claude.app" > /dev/null 2>&1; then
  echo "ERROR: Claude Desktop is running. Please quit it first."; exit 1
fi

BACKUP=$(ls -dt ~/Claude.app.backup-* 2>/dev/null | head -1)
if [[ -z "$BACKUP" ]]; then
  echo "ERROR: No backup found matching ~/Claude.app.backup-*"; exit 1
fi

echo "Restoring from: $BACKUP"
sudo rm -rf /Applications/Claude.app
sudo cp -R "$BACKUP" /Applications/Claude.app
sudo codesign --force --deep --sign - /Applications/Claude.app 2>/dev/null
codesign --verify --verbose /Applications/Claude.app 2>&1

echo "Done! Claude Desktop has been reverted."
REVERT_SCRIPT

chmod +x "$INSTALL_DIR/reapply.sh" "$INSTALL_DIR/revert.sh"
ok "Installed to $INSTALL_DIR"
ok "  reapply.sh — re-patch after auto-updates"
ok "  revert.sh  — restore from backup"

# --- Done ---
echo ""
echo -e "${GREEN}${BOLD}┌─────────────────────────────────────────────┐${NC}"
echo -e "${GREEN}${BOLD}│  ✔ RTL support installed successfully!      │${NC}"
echo -e "${GREEN}${BOLD}└─────────────────────────────────────────────┘${NC}"
echo ""
echo -e "  ${BOLD}Next steps:${NC}"
echo "  1. Launch Claude Desktop"
echo "  2. Test with Hebrew: אני בונה פרויקט עם Next.js ו-TypeScript"
echo "  3. Test with Arabic: مرحبا بالعالم"
echo ""
echo -e "  ${BOLD}After an auto-update:${NC}  bash ~/.claude-rtl/reapply.sh"
echo -e "  ${BOLD}To undo everything:${NC}    bash ~/.claude-rtl/revert.sh"
echo ""
