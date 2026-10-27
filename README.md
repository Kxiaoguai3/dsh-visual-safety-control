# dsh-desktop-guard

A [DeepSeek Harness](https://github.com/deepseek-ai) plugin that gives the model a native
`desktop` tool: **screenshot the Windows screen, locate controls by their text, drive the
mouse/keyboard** — plus a **content policy** and **action verification** on top.

> **Fork notice.** This is a fork of
> [qingying012/dsh-desktop-control](https://github.com/qingying012/dsh-desktop-control) v0.1.3
> (MIT). The upstream implementation — bundled `assets/gui.ps1`, local Windows OCR, UIA tree,
> screenshot grid, `sequence` batching — is kept as-is; the original copyright notice is in
> [LICENSE](LICENSE) and the delta is recorded in [NOTICE](NOTICE) and [CHANGELOG.md](CHANGELOG.md).

**Why a fork instead of a new plugin?** The upstream already solves the hard, unglamorous part
(OCR/UIA/screenshot/input inside one PowerShell file, no Python). This fork adds what it lacks:
content-level safety and machine-checked action results.

> Windows only. `assets/gui.ps1` **must stay UTF-8 with BOM** — Windows PowerShell 5.1 reads a
> BOM-less file as ANSI and fails to parse the Chinese messages.

## What the fork adds

| Addition | What it does |
|---|---|
| **Content policy** (`dsh/policy.js`) | Refuses dangerous target labels (支付/删除/delete/pay…), sensitive windows (银行/Password…), credential-looking `type` payloads and denied key combos **before PowerShell is spawned**. Irreversible labels (发布/发送/提交…) trigger an `ask` decision through `tools/pre-execute`; without approval support they are denied. The model cannot opt out through arguments. |
| **`type` verification** | Activates the target window and **refuses to type when it cannot make it foreground**, refuses when the focused control is provably not editable, then pastes and **reads the value back** through UI Automation. |
| **`click` verification** | Hit-tests the point against the named window — comparing **root windows**, and accepting the **same-PID popup** windows apps open (search dropdowns, UWP frame hosts) — and refuses clicks that would land elsewhere; reports the focused control afterwards. Optional `expect` OCR-checks the landing area, and `verifyText` re-OCRs the window after the click. |
| **`find` precision** | `exact:true` matches whole lines only; ambiguity now **refuses to click** and lists candidates; `index:N` clicks an explicit match. |
| **Activation guard** | `activate` / `type` use a documented retry ladder (SetForegroundWindow → real title-bar click → verify), never the old fire-and-forget call. |

## Install

Local directory (development / first run):

```js
plugin_manager({ action: "install_bundle", target: "<absolute path to this package>" })
```

From npm (after publishing):

```js
plugin_manager({ action: "install_bundle", target: "dsh-desktop-guard" })
```

**Do not enable this alongside `dsh-desktop-control`:** both register a tool named `desktop`, and
a duplicate name in one layer fails activation. Disable the other bundle first.

## Actions

| action | What it does | Main args |
| :-- | :-- | :-- |
| `find` | Local OCR locates text and returns screen coordinates (optionally clicks). No image. | `text` / `window` / `click` / `exact` / `index` / `threshold` / `screen` |
| `elements` | UIA control list for a window: name + centre point, no image | `window` / `filter` / `depth` / `all` |
| `ocr` | Local OCR of an image: text + per-line boxes | `imagePath` / `filter` |
| `screenshot` | Save a PNG (cursor stamped by default) and return its path | `window` / `region` / `print` / `grid` / `cursor` / `maxWidth` |
| `windows` | List visible windows (HWND, PID, rect, title) | `top` |
| `click` | Move and click, or click a control by UIA name | `x` `y` / `uia` `invoke` / `window` / `verify` / `button` `count` |
| `move` / `drag` / `scroll` | Cursor movement | `x` `y` / `x2` `y2` / `amount` |
| `type` | Paste text (base64-encoded on the wire), verify focus and readback | `text` / `window` / `verify` |
| `key` | Key combo, e.g. `ctrl+s` | `key` |
| `activate` | Bring a window to the front (guarded) | `window` |
| `pos` / `wait` | Cursor position / sleep | — / `waitMs` |
| `sequence` | Run several actions in one call | `steps` |

All coordinates are **physical pixels** (per-monitor DPI awareness v2 inside the script).

## Content policy

Defaults are on. Matching is case-, width- and whitespace-insensitive (`删 除`, `ＤＥＬＥＴＥ`,
`Delete all messages` all match). User lists **replace** the defaults.

```yaml
- id: desktop-guard
  name: dsh-desktop-guard
  config:
    policy:
      enabled: true
      denyLabels: ['支付', '转账', '删除', 'delete', 'pay']
      sensitiveWindows: ['银行', 'Password', 'Bank']
      refuseSecrets: true
      denyKeys: ['alt+f4']
      irreversibleLabels: ['发布', '发送', '提交', '发表', 'publish', 'send', 'submit']
      irreversibleMode: ask        # ask | deny | allow
      maxSequenceDepth: 5
    verifyType: true
    verifyClick: true
```

Rules: label checks apply to `click`/`find` (`text` and `uia`); sensitive windows block every read
or drive action on that window (`windows`/`pos`/`wait` still work); `type` payloads matching
`sk-…`, `api_key=`, `密码：…` are refused; `sequence` steps are inspected recursively and inherit
the parent window, with a depth limit so nesting cannot bypass the rules. **Irreversible labels**
are gated separately: `ask` sends the call to the host for approval (falls back to denial when the
host has no approval support), `deny` refuses outright, `allow` leaves only `denyLabels` in force.
A refusal is a normal tool error with a message telling the model this is policy, not a malfunction.

**Coordinate clicks:** `click` by `x`/`y` supports `expect` (the landing area must contain this
text — OCR of the target window, or the popup under the point) and `verifyText` (after the click,
require this text to be visible). For irreversible actions always use text/UIA targets plus
`verifyText`; see [OPERATING-RULES.md](OPERATING-RULES.md).

## Verification semantics

`type` / `click` return a `verification` object:

| status | Meaning |
|---|---|
| `verified` | `type`: the control read back contains the typed text; `verifyText`: the window now shows the required text (`method: post-action-find`). |
| `unverified` | `type`: readback worked but does not contain the text (it may have been dropped); `verifyText`: the text was not found after the action. |
| `unknown` | `click`: the action was delivered and hit-tested, but the application outcome is not machine-checked; or UIA cannot read the focused control. |
| `refused` | The tool refused to act (wrong focus, activation failure, hit-test mismatch, `expect` mismatch, policy `ask` denied). Nothing was typed/clicked. |

Verification never retries an action and never upgrades `unknown` to `verified`.

## Configure

| Option | Default | Meaning |
| :-- | :-- | :-- |
| `enabled` | `true` | `false` registers no tool |
| `powershellPath` | `powershell.exe` | PowerShell executable |
| `timeoutMs` | `30000` | Per-call timeout |
| `screenshotDir` | `$DSH_HOME/desktop-control` | Where screenshots are saved |
| `screenshotMaxWidth` | `1440` | Long-edge cap; the reply states the scale |
| `screenshotGrid` | `false` | Stamp the labelled coordinate grid |
| `screenshotCursor` | `true` | Stamp the cursor crosshair |
| `keepShots` | `40` | Prune older screenshots |
| `elementsMaxRows` | `140` | Truncate `elements` (`all:true` disables) |
| `policy.*` | see above | Content policy |
| `verifyType` / `verifyClick` | `true` | Per-action verification default |

## Development notes (learned the hard way)

- **Keep `assets/gui.ps1` UTF-8 with BOM.** Editing tools that write without BOM break Windows
  PowerShell 5.1 parsing (the script then fails on Chinese strings).
- **Do not pass `--` to `gui.ps1` via `-File`.** PowerShell 5.1 fails argument binding
  ("A positional parameter cannot be found"); `type` therefore transports its payload as
  `-b64 <base64>`.
- `npm run selftest` covers argv construction, policy evaluation and parameter validation without
  touching the desktop. It is the only test that can run in CI.
- Reload the plugin after editing `dsh/index.js`; `assets/gui.ps1` is read at spawn time, so its
  edits apply on the next call.

## Lab test plan

See [TESTING.md](TESTING.md) for the checklist used with lab machines (safety cases, verification
cases, evidence to collect, and known-flaky areas).

## Limitations

- **`find` depends on OCR.** Short labels are misread (measured `AB01` → `ABOI`, `hello` →
  `he110`); use `exact`, longer strings, or `threshold` tuning. A miss returns the closest lines.
- **Coordinate clicks cannot be judged.** The policy inspects `text`/`uia`; a raw `click x,y` has no
  target semantics. Prefer `uia` / `find`.
- **Activation can fail** (foreground lock, elevated windows, unattended sessions). `type` and
  `activate` refuse instead of typing into the wrong window.
- **UIA is blind to Chromium/Electron/Qt painted content**; use `find`/screenshots for those.
- **Background capture is blank for some GPU-rendered apps** (`PrintWindow`); activate first.
- **Coordinate space is physical pixels**; screenshots may be scaled (`scale` in the reply).
- UAC secure desktop, lock screen, some games/anti-cheat/terminal apps cannot be driven.
- Windows only.

## Operating rules

**Take a fresh screenshot before every action** — the screenshot is the permission to act. Re-read
the window rect each time (windows move and controls shift), prefer OCR/UIA targets over raw
coordinates, and for irreversible actions screenshot before, act by text/UIA with `verify`, then
screenshot after to confirm the result. Full rules: [OPERATING-RULES.md](OPERATING-RULES.md).

## License

MIT, with the upstream copyright notice retained. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
