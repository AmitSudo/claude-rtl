# Claude Desktop RTL Support (macOS)

Add right-to-left (RTL) text rendering to [Claude Desktop](https://claude.ai/download) on macOS for Hebrew, Arabic, Persian, Urdu, and other RTL languages.


## What it does

- Detects RTL characters and sets text direction per element automatically
- Lists (ol/ul) render with numbers/bullets on the correct side
- Code blocks stay LTR
- Input box switches direction live as you type
- Works during streaming (MutationObserver-based)

## Quick start

**One-liner:**
```bash
curl -fsSL https://raw.githubusercontent.com/AmitSudo/claude-rtl/main/install.sh | bash
```

**Or clone and run:**
```bash
git clone https://github.com/AmitSudo/claude-rtl.git
cd claude-rtl
bash install.sh
```

**Or via Homebrew:**
```bash
brew install AmitSudo/claude-rtl/claude-rtl
```

The installer will:
1. Check that Claude Desktop is installed and not running
2. Create a backup at `~/Claude.app.backup-YYYYMMDD-HHMMSS`
3. Inject RTL JavaScript into the app
4. Disable the asar integrity fuse and re-sign the app

## After a Claude Desktop auto-update

A background watcher (LaunchAgent) detects updates and re-applies the patch automatically. No action needed.

If the watcher fails or you disabled it, re-apply manually:

```bash
bash ~/.claude-rtl/reapply.sh
```

## Uninstall

```bash
bash uninstall.sh
```

Or manually restore from backup:
```bash
bash ~/.claude-rtl/revert.sh
```

## Requirements

- macOS
- Claude Desktop installed at `/Applications/Claude.app`
- Node.js / npx
- Admin access (sudo)

## How it works

The installer extracts Claude Desktop's `app.asar`, adds a `rtl.js` file containing the RTL logic, and appends a small hook to the Electron main process that executes the RTL script in every renderer via `webContents.executeJavaScript()` on `did-finish-load`. The RTL script uses a MutationObserver to continuously process new DOM elements, detecting text direction per-element using first-strong-character analysis.

**What gets modified:**
- `app.asar` — `rtl.js` added + hook appended to main entry
- Integrity hashes updated in all `Info.plist` files (falls back to fuse disable if needed)
- App re-signed with ad-hoc signature

## Credits

- RTL JavaScript logic by [shraga100](https://github.com/shraga100/claude-desktop-rtl-patch)
- macOS adaptation inspired by [toboly](https://github.com/toboly/claude-desktop-rtl-patch-mac)

## License

MIT
