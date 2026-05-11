# Claude Desktop RTL Support

Add right-to-left (RTL) text rendering to [Claude Desktop](https://claude.ai/download) for Hebrew, Arabic, Persian, Urdu, and other RTL languages.

<div dir="rtl">

**תמיכה בעברית, ערבית ושפות RTL נוספות באפליקציית Claude Desktop.**

</div>

## Before / After

| Without patch | With patch |
|---|---|
| Hebrew/Arabic text renders left-to-right ← | Text correctly flows right-to-left → |
| Mixed content looks broken | Code stays LTR, prose flows naturally |

## How it works

The installer patches Claude Desktop's Electron main process to inject CSS via `webContents.insertCSS()` on every page load. The CSS uses `unicode-bidi: plaintext` so the browser automatically detects text direction per paragraph — Hebrew and Arabic flow RTL while code blocks stay LTR.

**What gets modified:**
- `app.asar` — the RTL CSS injection hook is appended to the main entry file
- Electron fuse `EnableEmbeddedAsarIntegrityValidation` is set to `off` (required to load the modified asar)
- The app is re-signed with an ad-hoc signature

## Quick start

```bash
git clone https://github.com/YOUR_USERNAME/claude-rtl.git
cd claude-rtl
bash install.sh
```

The installer will:
1. Check that Claude Desktop is installed and not running
2. Create a backup at `~/Claude.app.backup-YYYYMMDD-HHMMSS`
3. Patch the app and re-sign it
4. Install helper scripts to `~/.claude-rtl/`

## After a Claude Desktop auto-update

Auto-updates will overwrite the patch. Re-apply it with:

```bash
bash ~/.claude-rtl/reapply.sh
```

Or re-run `bash install.sh` from this repo.

## Uninstall

```bash
bash uninstall.sh
```

Or manually:
```bash
bash ~/.claude-rtl/revert.sh
```

## Requirements

- macOS
- Claude Desktop installed at `/Applications/Claude.app`
- Node.js / npx
- Admin access (sudo) for modifying the app bundle

## FAQ

**Will this break Claude Desktop?**
A full backup is created before any changes. If anything goes wrong, run `bash uninstall.sh` to restore the original app.

**Does this survive auto-updates?**
No — Claude Desktop updates replace `app.asar`. Run `bash ~/.claude-rtl/reapply.sh` after each update.

**Does this affect code blocks?**
No. Code blocks, `<pre>`, `<code>`, and elements with code-related class names are forced to LTR direction.

**Is this an official Anthropic tool?**
No. This is a community patch. Use at your own risk.

## License

MIT
