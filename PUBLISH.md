# Publish

## 1. GitHub

The repository lives at <https://github.com/Kxiaoguai3/dsh-visual-safety-control>. To push a change:

```powershell
cd dsh-visual-safety-control
git add -A
git commit -m "feat: ..."
git push
```

On GitHub: **About → Topics** add `dsh-plugin` (plus `dsh`, `deepseek-harness`, `desktop`,
`windows`, `ocr`, `automation`, `safety`).

## 2. Verify from a clean checkout

```powershell
git clone https://github.com/Kxiaoguai3/dsh-visual-safety-control.git clean-check
cd clean-check
node scripts/selftest.mjs
$b = [IO.File]::ReadAllBytes((Resolve-Path 'assets/gui.ps1'))
($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
```

Expected: `selftest ok` and `True`. `.gitattributes` marks `*.ps1 -text`, and CI runs the same two
checks on every push.

## 3. npm

The name `dsh-visual-safety-control` is free as of 2026-10-27 (`npm view` → 404 on
registry.npmjs.org).

```powershell
cd dsh-visual-safety-control
# 0) sanity: manifest, BOM, tarball content; publishes nothing
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/publish.ps1 -DryRun

# 1) log in — one interactive step; must target the real registry
npm login --registry=https://registry.npmjs.org
npm whoami --registry=https://registry.npmjs.org

# 2) publish (2FA accounts: add --otp=<6 digits>, or use the script)
npm publish --registry=https://registry.npmjs.org --access public

# 3) verify
npm view dsh-visual-safety-control version dist.tarball --registry=https://registry.npmjs.org
```

`scripts/publish.ps1` runs the same steps plus a login check and a "version already exists" check;
`-Otp 123456` publishes without prompting.

**Registry pitfall:** the default registry on this machine is `https://registry.npmmirror.com`
(a read-only mirror). Always pass `--registry=https://registry.npmjs.org` when publishing.

**2FA:** accounts with two-factor authentication need either `--otp <code>` or a granular access
token with **Bypass 2FA** enabled (set it as `//registry.npmjs.org/:_authToken` in `~/.npmrc`).

**Old package:** `dsh-desktop-guard@0.2.1` was the previous name and is still on the registry.
After the new name is published, deprecate it:

```powershell
npm deprecate dsh-desktop-guard "Renamed to dsh-visual-safety-control; install that instead."
```

## 4. GitHub Release

Tag the commit that matches the published npm version:

```powershell
git tag 0.3.0
git push origin 0.3.0
```

Create the Release from that tag with `CHANGELOG.md` as the body.

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

- `0.3.x`: bug fixes and policy-list updates.
- `0.4.x`: new verified actions or policy rules (still opt-in).
- `1.0.0` only after the lab pass covers at least two Windows versions and both single/multi-monitor
  setups.
