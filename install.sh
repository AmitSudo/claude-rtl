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

# Copy rtl.js into the asar (download if running via curl|bash)
REPO_URL="https://raw.githubusercontent.com/AmitSudo/claude-rtl/main"
RTL_JS_SRC="$SCRIPT_DIR/rtl.js"
if [[ ! -f "$RTL_JS_SRC" ]]; then
  RTL_JS_SRC=$(mktemp)
  curl -fsSL "$REPO_URL/rtl.js" -o "$RTL_JS_SRC" || fail "Failed to download rtl.js"
  ok "Downloaded rtl.js from GitHub"
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

# --- Step 6: Update integrity hashes & re-sign ---
step "Updating integrity hashes & re-signing"

# Compute old and new asar header hashes
compute_asar_hash() {
  python3 -c "
import sys, struct, hashlib
with open(sys.argv[1], 'rb') as f:
    f.seek(12)
    size = struct.unpack('<I', f.read(4))[0]
    data = f.read(size)
print(hashlib.sha256(data.decode('utf-8').encode('utf-8')).hexdigest())
" "$1"
}

OLD_HASH=$(compute_asar_hash "$BACKUP_PATH/Contents/Resources/app.asar" 2>/dev/null || echo "")
NEW_HASH=$(compute_asar_hash "$ASAR")

if [[ -n "$OLD_HASH" && "$OLD_HASH" != "$NEW_HASH" ]]; then
  ok "Old hash: $OLD_HASH"
  ok "New hash: $NEW_HASH"

  PLISTS=(
    "$APP/Contents/Info.plist"
    "$APP/Contents/Frameworks/Electron Framework.framework/Versions/A/Resources/Info.plist"
    "$APP/Contents/Frameworks/Claude Helper.app/Contents/Info.plist"
    "$APP/Contents/Frameworks/Claude Helper (GPU).app/Contents/Info.plist"
    "$APP/Contents/Frameworks/Claude Helper (Plugin).app/Contents/Info.plist"
    "$APP/Contents/Frameworks/Claude Helper (Renderer).app/Contents/Info.plist"
  )

  UPDATED=0
  for plist in "${PLISTS[@]}"; do
    [[ -f "$plist" ]] || continue
    if grep -q "$OLD_HASH" "$plist" 2>/dev/null; then
      sudo sed -i '' "s/$OLD_HASH/$NEW_HASH/g" "$plist"
      ok "Updated: $(echo "$plist" | sed "s|$APP/||")"
      ((UPDATED++))
    fi
  done
  ok "Updated $UPDATED plist file(s)"
else
  warn "Could not compute hash diff — falling back to fuse disable"
  sudo npx --yes @electron/fuses write --app "$APP" EnableEmbeddedAsarIntegrityValidation=off 2>/dev/null
  ok "Asar integrity fuse disabled"
fi

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

compute_asar_hash() {
  python3 -c "
import sys, struct, hashlib
with open(sys.argv[1], 'rb') as f:
    f.seek(12)
    size = struct.unpack('<I', f.read(4))[0]
    data = f.read(size)
print(hashlib.sha256(data.decode('utf-8').encode('utf-8')).hexdigest())
" "$1"
}

echo "Computing old asar hash..."
OLD_HASH=$(compute_asar_hash "$ASAR")

echo "Repacking app.asar..."
sudo npx --yes @electron/asar pack "$WORK_DIR/claude-asar" "$ASAR" 2>/dev/null

echo "Computing new asar hash..."
NEW_HASH=$(compute_asar_hash "$ASAR")

if [[ "$OLD_HASH" != "$NEW_HASH" ]]; then
  echo "Updating integrity hashes in Info.plist files..."
  for plist in \
    "$APP/Contents/Info.plist" \
    "$APP/Contents/Frameworks/Electron Framework.framework/Versions/A/Resources/Info.plist" \
    "$APP/Contents/Frameworks/Claude Helper.app/Contents/Info.plist" \
    "$APP/Contents/Frameworks/Claude Helper (GPU).app/Contents/Info.plist" \
    "$APP/Contents/Frameworks/Claude Helper (Plugin).app/Contents/Info.plist" \
    "$APP/Contents/Frameworks/Claude Helper (Renderer).app/Contents/Info.plist"; do
    [[ -f "$plist" ]] || continue
    grep -q "$OLD_HASH" "$plist" 2>/dev/null && sudo sed -i '' "s/$OLD_HASH/$NEW_HASH/g" "$plist"
  done
fi

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

# Install watcher
if [[ -f "$SCRIPT_DIR/watcher.sh" ]]; then
  cp "$SCRIPT_DIR/watcher.sh" "$INSTALL_DIR/watcher.sh"
  chmod +x "$INSTALL_DIR/watcher.sh"
elif [[ -f "$INSTALL_DIR/watcher.sh" ]]; then
  : # already installed
else
  # Download watcher for curl|bash installs
  curl -fsSL "https://raw.githubusercontent.com/AmitSudo/claude-rtl/main/watcher.sh" \
    -o "$INSTALL_DIR/watcher.sh" 2>/dev/null && chmod +x "$INSTALL_DIR/watcher.sh" || true
fi

# Install LaunchAgent for auto-reapply
AGENT_LABEL="com.claude-rtl.watcher"
AGENT_PLIST="$HOME/Library/LaunchAgents/${AGENT_LABEL}.plist"

# Unload existing agent if present
launchctl bootout "gui/$(id -u)/$AGENT_LABEL" 2>/dev/null || true

cat > "$AGENT_PLIST" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${AGENT_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${INSTALL_DIR}/watcher.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${INSTALL_DIR}/watcher-stdout.log</string>
    <key>StandardErrorPath</key>
    <string>${INSTALL_DIR}/watcher-stderr.log</string>
</dict>
</plist>
PLIST

launchctl bootstrap "gui/$(id -u)" "$AGENT_PLIST" 2>/dev/null || true
ok "Auto-reapply watcher installed (LaunchAgent)"

# --- Done ---
echo ""
echo -e "${GREEN}${BOLD}┌─────────────────────────────────────────────┐${NC}"
echo -e "${GREEN}${BOLD}│  ✔ RTL support installed successfully!      │${NC}"
echo -e "${GREEN}${BOLD}└─────────────────────────────────────────────┘${NC}"
echo ""
echo -e "  ${BOLD}Next steps:${NC}"
echo "  1. Launch Claude Desktop"
echo "  2. Test by sending a message in Hebrew or Arabic"
echo "  3. Verify lists render with bullets/numbers on the correct side"
echo ""
echo -e "  ${BOLD}Auto-reapply:${NC}  Enabled — patch is re-applied automatically after updates"
echo -e "  ${BOLD}Manual reapply:${NC}  bash ~/.claude-rtl/reapply.sh"
echo -e "  ${BOLD}Undo everything:${NC}  bash uninstall.sh"
echo ""
