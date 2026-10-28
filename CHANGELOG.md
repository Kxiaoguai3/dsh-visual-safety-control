# Changelog

## 0.4.1 — GitHub Packages mirror

- New workflow `.github/workflows/publish-github-packages.yml`: on demand (or on a `v*` tag) it
  renames the package to `@<owner>/dsh-visual-safety-control` and publishes the same code to
  GitHub Packages, so the repository's **Packages** panel lists it. The npmjs release stays unscoped.
- Settings page now also resolves the plugin entry when it is installed from the scoped
  GitHub Packages name (`@owner/dsh-visual-safety-control`), not just the unscoped npm name.

## 0.4.0 — policy editable in Settings

- New settings page: **Settings → Plugins → 视觉安全 / Visual safety** (client half `dsh/client.js`).
  Edits the volatile `policy` config through the host's settings service, so values persist in the
  profile patch and apply on the next tool call without a restart.
- Plugin `Config` schema now declares every option with defaults, and `policy` is volatile.
- Host JSON route `/dsh-visual-safety-control/policy.json` (loopback only) backs the page.
- Tool name, action surface and policy semantics are unchanged.

## 0.3.1 — first npm release under the new name

- Republish after a staged `0.3.0` publish attempt left that version reserved on the registry
  (npm returns `E409 Cannot publish over previously staged version`). No code changes.

## 0.3.0 — renamed to dsh-visual-safety-control

- Package, bundle row and plugin name renamed from `dsh-desktop-guard` / `desktop-guard`
  to `dsh-visual-safety-control` / `visual-safety-control`. Tool name stays `desktop`.
- README restructured: `README.md` is now Chinese by default, English moved to `README.en.md`.
- Install hint and docs updated for the new name; npm users should switch to the new package.

## 0.2.1 — P0 fixes from the real-session run

### Added

- `click` `expect`: OCR-checks the landing area (target window via `PrintWindow`, or the popup under
  the point) and refuses when the text is missing — catches stale coordinates after layout shifts.
- `click`/`find` `verifyText`: after the action, OCR the window and attach
  `verification.status: verified|unverified` (`method: post-action-find`).
- Irreversible actions: `policy.irreversibleLabels` + `policy.irreversibleMode: ask|deny|allow`
  (default `ask`). The plugin registers `tools/pre-execute` and returns an `ask` decision; without
  approval support the action is denied. Hard `denyLabels` still win.
- Hit-test compares **root windows** and accepts **same-PID popups**: WeChat search dropdowns
  (separate `Weixin` window) and UWP apps under `ApplicationFrameHost` are no longer false-refused.

### Fixed

- `expect` no longer OCRs the screen when the target window is occluded (it used to read whichever
  window was on top and could refuse a correct click).
- `hitTest.method` now reports `hwnd` / `same-pid-popup`.

### Tests

- selftest: irreversible ask/deny/allow, deny-label precedence, nested sequence path, `-expect` argv.
- Live Windows 11: expect mismatch refusal, expect hit, same-PID popup click
  (`hitTest.method: same-pid-popup`), `verifyText` post-action find, irreversible ask rejection.

## 0.2.0 — fork of dsh-desktop-control 0.1.3

Upstream: [qingying012/dsh-desktop-control](https://github.com/qingying012/dsh-desktop-control) v0.1.3 (MIT).

### Added

- **Content policy** (`dsh/policy.js`): `denyLabels`, `sensitiveWindows`, `refuseSecrets`,
  `denyKeys`, `maxSequenceDepth`. Evaluated in Node before PowerShell is spawned; matching is
  case/width/whitespace insensitive; sequence steps are inspected recursively with the parent
  window inherited.
- **`type` verification**: guarded activation (SetForegroundWindow retry, then a real title-bar
  click, then verify), refusal when the target cannot be made foreground, refusal when the focused
  control is provably not editable, and a UI Automation readback verdict
  (`verified` / `unverified` / `unknown`).
- **`click` verification**: `WindowFromPoint` + `GetAncestor(GA_ROOT)` hit-test against the named
  window before clicking, refusal on mismatch, focused-control report afterwards.
- **`find` precision**: `exact` line matching, `index` selection, and ambiguity refusal with
  candidate list instead of clicking the best score blindly.
- `activate` now uses the guarded activation ladder.
- `type` transports text as `-b64` because PowerShell 5.1 `-File` binding rejects `--`.
- `scripts/selftest.mjs`: policy tests plus argv tests for the new parameters.
- `README.md`, `README.zh.md`, `NOTICE`, `TESTING.md`.

### Changed

- Package renamed to `dsh-desktop-guard`; bundle row id `desktop-guard`.
- Tool description documents policy and verification.
- Default behaviour is stricter: `verifyType` / `verifyClick` are on; policy is on.

### Kept from upstream

- Bundled `assets/gui.ps1` architecture (PowerShell 5.1, no Python), Windows.Media.Ocr,
  UIA element tree, screenshot grid/cursor/scale, `PrintWindow` fallback, `sequence` batching,
  per-call PowerShell process, physical-pixel coordinates.

### Known issues inherited

- Coordinate-only clicks cannot be judged by the policy.
- UIA is blind to Chromium/Electron/Qt painted content.
- `PrintWindow` returns blank for some GPU-rendered windows.
- `find` OCR misreads short labels.

### Development notes

- `assets/gui.ps1` must remain UTF-8 **with BOM**.
- Reload the plugin after editing `dsh/index.js`; `assets/gui.ps1` is read at spawn time.
