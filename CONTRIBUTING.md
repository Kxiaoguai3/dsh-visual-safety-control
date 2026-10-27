# Contributing

Thanks for testing! The most valuable reports are the ones where the plugin did the wrong thing or
refused something it should have allowed.

## Before you open an issue

1. Read [TESTING.md](TESTING.md) — run §0 (static checks) and the relevant case.
2. Make sure the other `desktop` tool (`dsh-desktop-control`) is disabled; two bundles cannot both
   register a tool named `desktop`.
3. Collect: Windows build, DPI scale, monitor layout, OCR language, the exact tool call, the tool
   result, and the screenshot path (redact personal data).

## Issue template

```text
Environment: Windows 11 23H2, 150% DPI, 2 monitors, zh-CN OCR
Plugin: dsh-visual-safety-control 0.3.0 (bundle row visual-safety-control)
Call: desktop { action: "click", ... }
Expected: ...
Actual: ... (paste the full tool error/output)
Screenshot: (path or attached; redact chats/accounts)
Repeats: always / intermittent (n/m)
```

Classify the failure if you can: **policy gap** (should have refused but did not), **verification
gap** (acted but reported the wrong verdict), **OCR limitation** (short/misread labels), **activation
limitation** (foreground lock, UAC, unattended session), **upstream behaviour**.

## Pull requests

- Keep `assets/gui.ps1` UTF-8 **with BOM** (CI checks it) and run `node scripts/selftest.mjs`.
- Update `CHANGELOG.md` and add a case to `TESTING.md` when behaviour changes.
- Never commit screenshots, tokens, chat logs, or personal paths.
- Policy changes need a test in `scripts/selftest.mjs`; verification changes need a note in the
  README table that explains the new `verification.status` value.

## Local development

```powershell
# install the checked-out directory into a scratch profile
plugin_manager({ action: "install_bundle", target: "<absolute path to this folder>" })
node scripts/selftest.mjs
```

After editing `dsh/index.js` reload the plugin; `assets/gui.ps1` is read at spawn time.
