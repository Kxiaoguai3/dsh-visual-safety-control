# Lab test plan

Goal: prove that every claimed behaviour is **observable** on a real Windows desktop, including the
refusal paths, before the plugin is published. Run once per release on a scratch account or VM.

## Preconditions

- Windows 10/11 x64, DSH Desktop running, PowerShell 5.1 available (`powershell.exe`).
- Windows OCR language pack installed (`Settings → Time & language → Language → Optical character recognition`), otherwise `find`/`ocr` fail.
- **Not** a locked/RDP-disconnected/UAC-prompting session; desktop is unlocked and interactive.
- Nothing valuable open: use a scratch Notepad document and a dummy "银行测试" text file for the sensitive-window case.

## 0. Static checks (no desktop interaction, CI-able)

```powershell
npm run selftest        # argv construction + policy evaluation
# gui.ps1 must parse AND carry a UTF-8 BOM
$b=[IO.File]::ReadAllBytes('assets/gui.ps1'); ($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
powershell -NoProfile -ExecutionPolicy Bypass -File assets/gui.ps1 pos
```

Expected: `selftest ok`, `True`, cursor coordinates.

## 1. Install / rollback

1. Disable the other desktop plugin: `plugin_manager({ action:"set_bundle", target:"dsh-desktop-control", enabled:false })`.
2. Install this package from its directory; expect `application: "applied"`, no warnings.
3. Smoke: `desktop({action:"windows", top:5})` returns a window table.
4. Rollback: disable this bundle, re-enable the other one. Environment must be usable again.

## 2. Safety cases (must refuse, and must not touch the desktop)

| ID | Steps | Expected |
|---|---|---|
| S1 | `find` text `删除` in any window | Tool error containing `策略拒绝` / `POLICY`; no OCR/click performed |
| S2 | Open a text file named `银行测试.txt`; `screenshot` with `window:"银行测试"` | Refused as sensitive window; no PNG saved |
| S3 | `type` text `sk-live-abcdefghijkl` into Notepad | Refused as credential payload; Notepad unchanged |
| S4 | Configure `denyKeys:['alt+f4']`; `key:"alt+f4"` | Refused; Notepad still open |
| S5 | `sequence` whose second step clicks `删除` | Refused with `steps[1]` in the message; first step still executes? (document if it does) |

Record the exact tool error text; it must say this is policy, not a tool failure.

## 3. Verification cases

| ID | Steps | Expected |
|---|---|---|
| V1 | Open an existing empty `scratch.txt` in Notepad; `type` text `hello-guard-123` with `window:"scratch"` | `Verification: verified (uia-value)`; the document contains the text |
| V2 | Open Notepad's save dialog (or a dialog with buttons); `type` with that window | `refused`: focused control is a button, nothing typed |
| V3 | `click` x=5 y=5 with `window:"scratch"` | `refused`: hit-test mismatch, no click |
| V4 | `click` the Notepad body with `window:"scratch"` | `Hit-test: ok`, `Verification: unknown (hit-test)` |
| V5 | `type` into an app whose window cannot be made foreground (elevated title, unattended session) | `refused` with "未能切到前台"; nothing typed elsewhere |

## 4. `find` precision

Prepare a scratch document with lines `ALFA` and `ALFA2`.

| ID | Steps | Expected |
|---|---|---|
| F1 | `find` `ALFA` `click:true` | Output `ambiguous|…` for both lines plus `# click refused: 2 matches`; no click |
| F2 | `find` `ALFA` `exact:true` `click:true` | Exactly one match (`ALFA`) and `clicked left @ …` |
| F3 | `find` `ALFA` `click:true` `index:2` | Clicks the second candidate |
| F4 | Query a string not on screen | `notfound` plus up to 3 `closest|` lines; no exception |

## 5. Core regressions from upstream

| ID | Steps | Expected |
|---|---|---|
| R1 | `screenshot` full screen, then `region`, then `maxWidth:800` | PNG paths; sizes/`scale` reported; grid labels only with `grid:true` |
| R2 | `elements` on Notepad | UIA rows with names/centres; `filter` narrows |
| R3 | `ocr` on a screenshot PNG | text + boxes |
| R4 | `sequence` [click, wait, type] | one call, actions in order, one PowerShell process |
| R5 | `activate` a background window | foreground becomes that window (`fg` confirms) |

## 6. Evidence to keep

- Exact tool call + result text for S1–S5, V1–V5, F1–F3.
- PNG paths for R1 (and one screenshot of a successful `find` click).
- Environment line: Windows build, DPI scale, monitor layout, OCR language tag.
- **Redact** personal chat/bank content; never commit screenshots of real accounts.

## 7. Known-flaky areas (report, do not hide)

- Short OCR labels (`AB01` → `ABOI`, `hello` → `he110`); `exact`/`threshold` mitigate.
- Modal dialogs appear as the "focused control" — `type` refuses (intended), but the test must dismiss the dialog.
- Elevated/UIPI windows and unattended sessions cannot be activated; refusal is expected.
- `PrintWindow` blank for some GPU windows; activate first.
- Single-instance Notepad reuses an existing window/tab, so window titles change (`*name - Notepad`).

## 7.5 Cases added from the 2026-10-27 real-session run

These are the cases the first end-to-end run actually hit; keep them in regression.

| ID | Scenario | Expected |
|---|---|---|
| B1 | Browse a feed: screenshot, scroll, screenshot | Each screen is read before the next action; scroll lands inside the list; no post card is opened by accident |
| B2 | Window moves between steps (re-tile, user drag) | The next action re-reads the window rect; stale coordinates are refused by hit-test, not silently mis-clicked |
| P1 | Publish a post (irreplaceable action) | Screenshot before (target/partition/text), click by text/OCR rather than stale coordinates, screenshot after, then **verify by finding the post text in the feed** — never claim success from the click alone |
| P2 | Same-process popup (search dropdown is a separate `Weixin` window) | Hit-test must accept windows of the **same PID**; today it refuses and the caller works around by using the popup title — fix candidate: compare PIDs |
| V6 | Layout shifts after typing (button moves ~40px) | Re-locate the button (`find`/OCR) after typing; a stale click lands on empty space and reports `unknown` — treat that as "not verified" |

## 8. Regression checklist for a PR

0. Every action was preceded by a fresh screenshot (see [OPERATING-RULES.md](OPERATING-RULES.md)).
1. `npm run selftest` green.
2. BOM + parse check green.
3. At least S1, V1, V3, F1, F2 re-run and evidence attached.
4. `CHANGELOG.md` updated.
5. No personal paths, screenshots, tokens, or account data in the diff.
