#!/bin/bash
set -euo pipefail

# ============================================================
#  Claude Desktop — RTL Support Installer
#  Adds right-to-left text rendering for Hebrew, Arabic, etc.
# ============================================================

APP="/Applications/Claude.app"
ASAR="$APP/Contents/Resources/app.asar"
INSTALL_DIR="$HOME/.claude-rtl"

# --- Colors & helpers ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

step=0
step() { step=$((step+1)); echo -e "\n${BLUE}${BOLD}[$step/$total_steps]${NC} $1"; }
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

if [[ ! -f "$MAIN_FILE" ]]; then
  fail "Main entry file not found: $MAIN"
fi
ok "Main entry: $MAIN"

if grep -q "RTL injection hook" "$MAIN_FILE"; then
  ok "RTL patch is already present — skipping"
else
  cat >> "$MAIN_FILE" << 'PATCH'

// --- RTL injection hook (added manually for Hebrew/Arabic support) ---
try {
  const { app: __rtlApp } = require('electron');
  const __RTL_CSS = `
    body, body p, body li, body ul, body ol, body div, body span, body td, body th,
    body blockquote, body h1, body h2, body h3, body h4, body h5, body h6 {
      unicode-bidi: plaintext;
    }
    pre, code, pre *, code *, .hljs, .hljs *,
    [class*="code"], [class*="Code"] {
      direction: ltr !important;
      unicode-bidi: embed !important;
      text-align: left !important;
    }
    textarea, input[type="text"], [contenteditable="true"], [contenteditable=""] {
      unicode-bidi: plaintext;
    }
  `;
  __rtlApp.on('web-contents-created', (_e, contents) => {
    contents.on('did-finish-load', () => {
      contents.insertCSS(__RTL_CSS).catch(() => {});
    });
  });
} catch (_e) {}
// --- end RTL injection hook ---
PATCH
  ok "RTL CSS injection hook added"
fi

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

cat > "$INSTALL_DIR/reapply.sh" << 'REAPPLY_SCRIPT'
#!/bin/bash
set -euo pipefail
APP="/Applications/Claude.app"
ASAR="$APP/Contents/Resources/app.asar"

if pgrep -f "Claude.app" > /dev/null 2>&1; then
  echo "ERROR: Claude Desktop is running. Please quit it first."; exit 1
fi
if [[ ! -d "$APP" ]]; then
  echo "ERROR: Claude Desktop not found."; exit 1
fi

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

echo "Extracting app.asar..."
npx --yes @electron/asar extract "$ASAR" "$WORK_DIR/claude-asar" 2>/dev/null

MAIN=$(python3 -c "import json; print(json.load(open('$WORK_DIR/claude-asar/package.json'))['main'])")
MAIN_FILE="$WORK_DIR/claude-asar/$MAIN"

if [[ ! -f "$MAIN_FILE" ]]; then
  echo "ERROR: Main entry file not found: $MAIN"; exit 1
fi

if grep -q "RTL injection hook" "$MAIN_FILE"; then
  echo "RTL patch is already applied."; exit 0
fi

echo "Applying RTL patch..."
cat >> "$MAIN_FILE" << 'PATCH'

// --- RTL injection hook (added manually for Hebrew/Arabic support) ---
try {
  const { app: __rtlApp } = require('electron');
  const __RTL_CSS = `
    body, body p, body li, body ul, body ol, body div, body span, body td, body th,
    body blockquote, body h1, body h2, body h3, body h4, body h5, body h6 {
      unicode-bidi: plaintext;
    }
    pre, code, pre *, code *, .hljs, .hljs *,
    [class*="code"], [class*="Code"] {
      direction: ltr !important;
      unicode-bidi: embed !important;
      text-align: left !important;
    }
    textarea, input[type="text"], [contenteditable="true"], [contenteditable=""] {
      unicode-bidi: plaintext;
    }
  `;
  __rtlApp.on('web-contents-created', (_e, contents) => {
    contents.on('did-finish-load', () => {
      contents.insertCSS(__RTL_CSS).catch(() => {});
    });
  });
} catch (_e) {}
// --- end RTL injection hook ---
PATCH

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
