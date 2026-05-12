# Claude Desktop RTL Support (macOS)

Add right-to-left (RTL) text rendering to [Claude Desktop](https://claude.ai/download) on macOS for Hebrew, Arabic, Persian, Urdu, and other RTL languages.

## What it does

- Detects RTL characters and sets text direction per element automatically
- Lists (ol/ul) render with numbers/bullets on the correct side
- Code blocks stay LTR
- Input box switches direction live as you type
- Works during streaming (MutationObserver-based)

## How it works

The installer creates a **separate, patched copy** of Claude Desktop at `~/Applications/Claude-RTL.app`. The original `/Applications/Claude.app` is never modified.

- **Open Claude-RTL.app** for Hebrew/Arabic chats — RTL works.
- **Open Claude.app** for features that require Anthropic's original signed bundle (e.g., **Cowork**). Both apps share login state and history because they have the same bundle identifier.

You can't run both at the same time (macOS prefers one bundle ID), but switching is just "quit one, open the other."

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

## After a Claude update

Anthropic ships updates to `/Applications/Claude.app` automatically. Those don't touch `~/Applications/Claude-RTL.app`, so the patched copy can fall behind. Refresh it by re-running the installer:

```bash
bash install.sh
```

This rebuilds the copy from the current source, so you pick up whatever the latest version is.

## Uninstall

```bash
bash uninstall.sh
```

Removes `~/Applications/Claude-RTL.app`. The original Claude.app stays exactly as it was.

## Requirements

- macOS
- Claude Desktop installed at `/Applications/Claude.app`
- Node.js / npx (for `@electron/asar` and `@electron/fuses`)
- **No sudo required** — everything happens in your home folder

## Why a copy instead of patching in-place?

Modifying the original Claude.app forces an ad-hoc re-sign, which Anthropic's Cowork integrity check rejects with `Invalid installation — Reinstall Claude to use Cowork`. By patching a copy instead:

- **Cowork keeps working** in the original app (signature intact)
- **No sudo** — `~/Applications/` is user-writable
- **No auto-update conflict** — Anthropic's updates go to the original; the patched copy is independent
- **Easy recovery** — if anything breaks, delete the copy

## Credits

- RTL detection logic adapted from [@shraga100/claude-desktop-rtl-patch](https://github.com/shraga100/claude-desktop-rtl-patch) (Windows)
- Copy-based install approach inspired by [@soguy/claude-desktop-rtl-mac](https://github.com/soguy/claude-desktop-rtl-mac)
- Earlier macOS in-place port: [@toboly/claude-desktop-rtl-patch-mac](https://github.com/toboly/claude-desktop-rtl-patch-mac)

## License

MIT
