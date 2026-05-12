#!/bin/bash
set -euo pipefail

# ============================================================
#  Claude Desktop — RTL Support Installer (macOS)
#
#  Builds a patched copy of Claude.app at ~/Applications/Claude-RTL.app.
#  The original /Applications/Claude.app is never modified, so features
#  that validate Anthropic's signature (Cowork, etc.) keep working
#  in the original app.
# ============================================================

SOURCE_APP="/Applications/Claude.app"
PATCHED_APP="$HOME/Applications/Claude-RTL.app"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_URL="https://raw.githubusercontent.com/AmitSudo/claude-rtl/main"

# --- Colors & helpers ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

step_n=0
total_steps=6
step() { step_n=$((step_n+1)); echo -e "\n${BLUE}${BOLD}[$step_n/$total_steps]${NC} $1"; }
ok()   { echo -e "  ${GREEN}✔${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }
fail() { echo -e "  ${RED}✖ $1${NC}"; exit 1; }

ask_yes() {
  read -rp "  → $1 [Y/n] " ans
  case "${ans:-Y}" in [Nn]*) return 1 ;; *) return 0 ;; esac
}

# --- Banner ---
echo ""
echo -e "${BOLD}┌─────────────────────────────────────────────┐${NC}"
echo -e "${BOLD}│  Claude Desktop — RTL Support Installer     │${NC}"
echo -e "${BOLD}│  Hebrew · Arabic · Persian · Urdu            │${NC}"
echo -e "${BOLD}└─────────────────────────────────────────────┘${NC}"
echo ""

# --- Step 1: Preflight ---
step "Preflight checks"

[[ "$(uname)" == "Darwin" ]] || fail "macOS only."
ok "Running on macOS"

[[ -d "$SOURCE_APP" ]] || fail "Claude Desktop not found at $SOURCE_APP. Install it from https://claude.ai/download"
ok "Source Claude.app found"

VERSION=$(defaults read "$SOURCE_APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "unknown")
ok "Source version: $VERSION"

command -v npx >/dev/null 2>&1 || fail "npx not found. Install Node.js: https://nodejs.org"
ok "npx available"

# Warn if the source itself looks patched (ad-hoc signed). Doesn't block install —
# the user can decide. The copy will be ad-hoc either way, but Cowork in the
# source will keep failing until they restore the source.
SOURCE_SIG=$(codesign -dvv "$SOURCE_APP" 2>&1 | grep -E "^(Signature|TeamIdentifier)=" || true)
if echo "$SOURCE_SIG" | grep -q "Signature=adhoc"; then
  warn "Source $SOURCE_APP appears to be ad-hoc signed (already patched?)."
  warn "Cowork won't work in the source until you reinstall Claude Desktop from claude.ai/download."
fi

# Stop the patched copy if it's running
if pgrep -f "Claude-RTL.app" >/dev/null 2>&1; then
  warn "Claude-RTL.app is running."
  if ask_yes "Quit Claude-RTL.app now?"; then
    pkill -f "Claude-RTL.app" 2>/dev/null || true
    sleep 2
    pgrep -f "Claude-RTL.app" >/dev/null 2>&1 && { pkill -9 -f "Claude-RTL.app" 2>/dev/null || true; sleep 1; }
    ok "Claude-RTL.app stopped"
  else
    fail "Please quit Claude-RTL.app and run this script again."
  fi
fi

# --- Step 2: Copy source → patched ---
step "Creating patched copy at $PATCHED_APP"

mkdir -p "$(dirname "$PATCHED_APP")"
if [[ -d "$PATCHED_APP" ]]; then
  warn "Existing copy found — replacing"
  rm -rf "$PATCHED_APP"
fi
cp -R "$SOURCE_APP" "$PATCHED_APP"
ok "Copied to $PATCHED_APP"

# Cosmetic: distinguish in Dock/Spotlight via CFBundleDisplayName.
# CFBundleName is left alone — changing it can break Electron's internal lookups.
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Claude-RTL" "$PATCHED_APP/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string Claude-RTL" "$PATCHED_APP/Contents/Info.plist" 2>/dev/null \
  || true
ok "Display name set to Claude-RTL"

# --- Step 3: Patch app.asar ---
step "Patching app.asar"

ASAR_PATH="$PATCHED_APP/Contents/Resources/app.asar"
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

npx --yes @electron/asar extract "$ASAR_PATH" "$WORK_DIR/claude-asar" 2>/dev/null
ok "Extracted"

MAIN=$(python3 -c "import json; print(json.load(open('$WORK_DIR/claude-asar/package.json'))['main'])")
MAIN_FILE="$WORK_DIR/claude-asar/$MAIN"
MAIN_DIR=$(dirname "$MAIN_FILE")
[[ -f "$MAIN_FILE" ]] || fail "Main entry file not found: $MAIN"
ok "Main entry: $MAIN"

# Copy rtl.js into the asar (download if running via curl|bash)
RTL_JS_SRC="$SCRIPT_DIR/rtl.js"
if [[ ! -f "$RTL_JS_SRC" ]]; then
  RTL_JS_SRC=$(mktemp)
  curl -fsSL "$REPO_URL/rtl.js" -o "$RTL_JS_SRC" || fail "Failed to download rtl.js"
  ok "Downloaded rtl.js from GitHub"
fi
cp "$RTL_JS_SRC" "$MAIN_DIR/rtl.js"
ok "rtl.js copied into asar"

# Remove any existing RTL hook (in case the source somehow has one)
if grep -q "RTL injection hook" "$MAIN_FILE"; then
  python3 -c "
import re
with open('$MAIN_FILE', 'r') as f: content = f.read()
content = re.sub(r'\n// --- RTL injection hook.*', '', content, flags=re.DOTALL)
with open('$MAIN_FILE', 'w') as f: f.write(content)
"
  ok "Removed stale RTL hook from source"
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
ok "Hook appended to main entry"

npx --yes @electron/asar pack "$WORK_DIR/claude-asar" "$ASAR_PATH" 2>/dev/null
ok "Repacked"

# --- Step 4: Disable asar integrity fuse ---
step "Disabling asar integrity fuse"

# The fuse verifies the asar header hash against a value embedded in the
# binary. After repacking the hash changes; without disabling the fuse,
# Electron refuses to start.
npx --yes @electron/fuses write --app "$PATCHED_APP" EnableEmbeddedAsarIntegrityValidation=off 2>/dev/null
ok "Fuse disabled"

# --- Step 5: Re-sign ad-hoc ---
step "Re-signing with ad-hoc signature"

# macOS dyld refuses to load binaries whose Team IDs disagree. After patching
# we re-sign every Mach-O, dylib, framework, helper .app, and finally the outer
# bundle — all ad-hoc (Team ID = "-") so everything is consistent.

# Mach-O binaries (executables + dylibs + .node native modules)
find "$PATCHED_APP" -type f \( -name "*.dylib" -o -perm +111 \) 2>/dev/null | while read -r f; do
  file "$f" 2>/dev/null | grep -q "Mach-O" && codesign --sign - --force "$f" 2>/dev/null || true
done

# Frameworks (deepest-first via find)
find "$PATCHED_APP" -name "*.framework" 2>/dev/null | while read -r fw; do
  codesign --sign - --force --deep "$fw" 2>/dev/null || true
done

# Helper .app bundles
find "$PATCHED_APP" -name "*.app" -not -path "$PATCHED_APP" 2>/dev/null | while read -r a; do
  codesign --sign - --force --deep "$a" 2>/dev/null || true
done

# Outer bundle
codesign --sign - --force --deep "$PATCHED_APP" 2>/dev/null
ok "App re-signed (ad-hoc)"

# --- Step 6: Launch ---
step "Launching Claude-RTL"

open "$PATCHED_APP"
ok "Launched"

# --- Done ---
echo ""
echo -e "${GREEN}${BOLD}┌─────────────────────────────────────────────┐${NC}"
echo -e "${GREEN}${BOLD}│  ✔ RTL support installed successfully!      │${NC}"
echo -e "${GREEN}${BOLD}└─────────────────────────────────────────────┘${NC}"
echo ""
echo -e "  ${BOLD}Patched copy:${NC}   $PATCHED_APP"
echo -e "  ${BOLD}Original:${NC}        $SOURCE_APP  ${YELLOW}(untouched — Cowork keeps working here)${NC}"
echo ""
echo "  Open Claude-RTL.app for Hebrew/Arabic chats. Open Claude.app for Cowork."
echo "  Both apps share login state via the same bundle identifier."
echo ""
echo -e "  ${BOLD}After a Claude update:${NC}  re-run this installer to refresh the copy."
echo -e "  ${BOLD}Uninstall:${NC}              bash uninstall.sh"
echo ""
