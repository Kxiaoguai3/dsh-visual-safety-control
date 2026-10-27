# Publishing checklist

Everything a maintainer needs to publish this fork. Do the steps in order; the first two are the
only ones that need decisions from the repository owner.

## 0. Before anything: metadata

`package.json` currently has no `repository` / `homepage` / `bugs`. Fill them once the GitHub repo
exists:

```json
"repository": { "type": "git", "url": "git+https://github.com/<YOUR_GH>/dsh-desktop-guard.git" },
"homepage": "https://github.com/<YOUR_GH>/dsh-desktop-guard#readme",
"bugs": { "url": "https://github.com/<YOUR_GH>/dsh-desktop-guard/issues" }
```

Keep `author` as a group name or your handle. Keep the upstream attribution in `NOTICE` and the
original MIT copyright in `LICENSE`; do not remove them.

## 1. Push to GitHub with the `dsh-plugin` topic

```powershell
cd dsh-desktop-guard
git init
git add -A
git commit -m "feat: dsh-desktop-guard 0.2.0 (fork with content policy and verification)"
# create an empty repo dsh-desktop-guard on GitHub, then:
git remote add origin https://github.com/<YOUR_GH>/dsh-desktop-guard.git
git branch -M main
git push -u origin main
```

On GitHub: **About → Topics** add `dsh-plugin` (plus `dsh`, `deepseek-harness`, `desktop`,
`windows`, `ocr`, `automation`). The topic page sorts by popularity, so a fresh 0-star repo sits at
the bottom — link it directly (e.g. from your school lab group) until it gets traction.

## 2. Verify from a clean checkout

```powershell
git clone https://github.com/<YOUR_GH>/dsh-desktop-guard.git dsh-desktop-guard-clean
cd dsh-desktop-guard-clean
npm run selftest
$b=[IO.File]::ReadAllBytes((Resolve-Path 'assets/gui.ps1')); ($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
```

Expected: selftest ok, `True`. The repo ships `.gitattributes` with `*.ps1 -text` so git keeps the
BOM byte-exact; the same checks run in CI (`.github/workflows/selftest.yml`) on every push.

## 3. npm

The name `dsh-desktop-guard` is still free on 2026-10-27 (`npm view` → 404 on registry.npmjs.org).

```powershell
cd dsh-desktop-guard
# 0) sanity: 15 files, ~50 kB, gui.ps1 keeps its BOM (verified 2026-10-27)
npm pack --dry-run --registry=https://registry.npmjs.org

# 1) log in — one interactive step, browser + OTP; must target the real registry
npm login --registry=https://registry.npmjs.org
npm whoami --registry=https://registry.npmjs.org

# 2) publish (2FA accounts: add --otp=<6 digits>)
npm publish --registry=https://registry.npmjs.org --access public

# 3) verify
npm view dsh-desktop-guard version dist.tarball --registry=https://registry.npmjs.org
```

**Registry pitfall:** this machine's default registry is `https://registry.npmmirror.com` (a
read-only mirror). `npm publish` without `--registry` fails or looks in the wrong place — always pass
`--registry=https://registry.npmjs.org`. The mirror syncs new packages automatically later, so users
installing through the mirror still get it (with delay).

Then install from npm into a scratch DSH profile:
`plugin_manager({ action:"install_bundle", target:"dsh-desktop-guard" })` → `application: "applied"`.

Publishing without an interactive login (e.g. CI): create an npm **Automation** token, expose it as
`NPM_TOKEN`, and add a release workflow (`npm publish --provenance --access public` with
`registry-url: https://registry.npmjs.org`).

If the name is taken later, publish under a scope: `@<scope>/dsh-desktop-guard` and update the
bundle patch `name:` accordingly.

## 4. Release notes (GitHub Release)

Use `CHANGELOG.md` as the body. Lead with the two additions (content policy, action verification)
and explicitly state the fork base and MIT attribution.

## 5. Lab rollout

1. Collect testers' Windows versions / DPI / monitor layout.
2. Each tester disables any other `desktop` tool (`dsh-desktop-control`) before enabling this one.
3. Run [TESTING.md](TESTING.md) §0–§5 on each machine and attach the evidence.
4. File every failure with: tool call, expected vs actual, screenshot path, Windows build, DPI.
5. Triage into: policy gap / verification gap / OCR limitation / activation limitation / upstream
   behaviour. Only the first two are this fork's bugs.

## 6. Security review before sharing widely

- The plugin can click and type anything; state that plainly in the README (done).
- Default policy list is opinionated; a user can disable it, which is documented.
- Coordinate-only clicks are not judged by policy — keep that limitation visible.
- Do not add telemetry, network calls, or bundled binaries without review; there are none today.
- Never publish collected screenshots from real accounts.

## 7. Versioning policy

- `0.2.x`: bug fixes and policy-list updates.
- `0.3.x`: new verified actions or policy rules (still opt-in).
- `1.0.0` only after the lab pass covers at least two Windows versions and both single/multi-monitor
  setups.
