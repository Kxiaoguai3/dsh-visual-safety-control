# dsh-visual-safety-control

[![npm](https://img.shields.io/npm/v/dsh-visual-safety-control)](https://www.npmjs.com/package/dsh-visual-safety-control)
[![CI](https://github.com/Kxiaoguai3/dsh-visual-safety-control/actions/workflows/selftest.yml/badge.svg)](https://github.com/Kxiaoguai3/dsh-visual-safety-control/actions/workflows/selftest.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A Windows desktop-control plugin for DeepSeek Harness. It gives the model a `desktop` tool: screenshots, local OCR, UI Automation control lookup, mouse and keyboard input — plus a content policy and action verification.

Forked from [qingying012/dsh-desktop-control](https://github.com/qingying012/dsh-desktop-control) v0.1.3 (MIT).

## Features

| Capability | What it does |
| :-- | :-- |
| Screenshot | Full screen, window or region; optional coordinate grid and cursor mark |
| OCR | Local Windows OCR, returns text and coordinates |
| Locate | Find by OCR text or UIA control name, filtered by window; refuses to click on ambiguity and lists candidates |
| Mouse | Coordinate click, UIA control click, move, drag, scroll |
| Keyboard | Paste text, key combos; checks the target window and editability first, reads the value back |
| Windows | List windows (HWND / PID / rect / title), activate one |
| Sequence | Run several steps in one call |

### Content policy

- Dangerous labels (pay, delete, uninstall, …): never clicked or located
- Sensitive windows (bank, password manager, wallet, credentials): never read or driven
- Credential-looking input: refused
- Dangerous key combos: refused
- Irreversible actions (publish, send, submit, buy): ask the user first

### Action verification

- `expect` checks the text under the click point before clicking, catching stale coordinates
- `verifyText` checks the window after the action
- Clicks are hit-tested; same-process popups and UWP windows are handled
- Typed text is read back through UI Automation

## Install

Local checkout:

```js
plugin_manager({ action: "install_bundle", target: "<absolute path to this repo>" })
```

From npm (after publishing):

```js
plugin_manager({ action: "install_bundle", target: "dsh-visual-safety-control" })
```

Do not enable this alongside `dsh-desktop-control`: both register a tool named `desktop`, and duplicate names fail activation.

## Usage

| action | Purpose | Main args |
| :-- | :-- | :-- |
| `find` | OCR text and return screen coordinates; can click | `text` / `window` / `click` / `exact` / `index` / `threshold` |
| `elements` | UIA control list (name + centre) | `window` / `filter` / `depth` / `all` |
| `ocr` | OCR an image | `imagePath` / `filter` |
| `screenshot` | Save a PNG, return its path | `window` / `region` / `print` / `grid` / `cursor` / `maxWidth` |
| `windows` | List visible windows | `top` |
| `click` | Click a point or a UIA control | `x` `y` / `uia` `invoke` / `window` / `expect` / `verifyText` / `button` `count` |
| `move` / `drag` / `scroll` | Pointer movement | `x` `y` / `x2` `y2` / `amount` |
| `type` | Paste text | `text` / `window` / `verify` |
| `key` | Key combo, e.g. `ctrl+s` | `key` |
| `activate` | Bring a window to the front | `window` |
| `pos` / `wait` | Cursor position / sleep | — / `waitMs` |
| `sequence` | Several steps in one call | `steps` |

All coordinates are physical pixels.

```js
desktop { action: "find", text: "Save", window: "Notepad" }

desktop { action: "click", x: 812, y: 460, window: "Notepad", expect: "Save", verifyText: "Saved" }

desktop { action: "type", text: "hello", window: "Notepad" }
```

## Configuration

```yaml
- id: visual-safety-control
  name: dsh-visual-safety-control
  config:
    policy:
      enabled: true
      denyLabels: ['pay', 'delete', 'uninstall', 'transfer']
      sensitiveWindows: ['Bank', 'Password', 'Wallet']
      refuseSecrets: true
      denyKeys: ['alt+f4']
      irreversibleLabels: ['publish', 'send', 'submit', 'buy']
      irreversibleMode: ask        # ask | deny | allow
      maxSequenceDepth: 5
    verifyType: true
    verifyClick: true
```

The policy runs before PowerShell is spawned; the model cannot disable it through tool arguments. User lists replace the defaults.

| Option | Default | Meaning |
| :-- | :-- | :-- |
| `enabled` | `true` | `false` registers no tool |
| `powershellPath` | `powershell.exe` | PowerShell executable |
| `timeoutMs` | `30000` | Per-call timeout |
| `screenshotDir` | `$DSH_HOME/desktop-control` | Where screenshots are saved |
| `screenshotMaxWidth` | `1440` | Long-edge cap |
| `screenshotGrid` / `screenshotCursor` | `false` / `true` | Coordinate grid / cursor mark |
| `keepShots` | `40` | Screenshots kept on disk |
| `elementsMaxRows` | `140` | `elements` row cap |
| `verifyType` / `verifyClick` | `true` | Verification defaults |

## Verification status

| Status | Meaning |
| :-- | :-- |
| `verified` | Readback contains the typed text, or `verifyText` found the expected content after the action |
| `unverified` | Readback worked but does not match, or the post-action text was not found |
| `unknown` | The action was delivered but the outcome cannot be machine-checked |
| `refused` | Not executed: wrong focus, foreground refused, hit-test mismatch, `expect` mismatch, or policy |

## Limitations

- Windows only, interactive desktop required; lock screen, UAC secure desktop and disconnected RDP sessions fail
- Coordinate clicks are not judged by the content policy; use `expect` / `verifyText`
- Short labels and similar glyphs can confuse OCR; use `exact` and `index`
- Irreversible actions default to `ask`; without host approval support they are denied

## Docs

- [TESTING.md](TESTING.md): test cases and acceptance checklist
- [OPERATING-RULES.md](OPERATING-RULES.md): operating rules
- [CHANGELOG.md](CHANGELOG.md): version history
- [CONTRIBUTING.md](CONTRIBUTING.md): issues and patches
- [PUBLISH.md](PUBLISH.md): release process

## Credits

Based on [qingying012/dsh-desktop-control](https://github.com/qingying012/dsh-desktop-control) (MIT). The original copyright notice is kept in [LICENSE](LICENSE); changes are recorded in [NOTICE](NOTICE) and [CHANGELOG.md](CHANGELOG.md).
