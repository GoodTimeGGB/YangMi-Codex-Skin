# Codex Woodland A1 Visual Revision Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task with review checkpoints.

**Goal:** Make the `woodland-white` renderer show Yang Mi as a clear right-side full-height visual while preserving native Codex readability and interaction.

**Architecture:** Keep the existing two-node renderer contract (`ym-veil` and `ym-portrait`) and change only the generated CSS in `shared/injector.mjs`. Extend the payload contract test to lock the A1 geometry and visibility rules, then synchronize the tested source into the installed skill before live verification.

**Tech Stack:** Node.js 22+, ES modules, PowerShell 7/Windows PowerShell adapters, Chromium CDP loopback injection.

---

### Task 1: Lock A1 renderer expectations with a failing test

**Files:**
- Modify: `skin-package/tests/test-renderer-payload.mjs`

- [ ] **Step 1: Add assertions for A1 CSS contract**

After the existing renderer report assertions, add checks that the generated script contains the right anchor, a readable desktop width, visible opacity, and a local transition fade:

```js
assert.match(report.rendererCss, /right:0/);
assert.match(report.rendererCss, /width:min\(62vw,820px\)/);
assert.match(report.rendererCss, /opacity:\.82/);
assert.match(report.rendererCss, /linear-gradient\(90deg/);
assert.equal(report.portraitHiddenAt, null);
```

The test must read these values from the JSON report rather than inspecting a duplicate CSS fixture.

- [ ] **Step 2: Run the focused test and confirm RED**

Run from `skin-package`:

```powershell
node .\tests\test-renderer-payload.mjs
```

Expected result: FAIL because the current report has no `rendererCss` field and still reports `portraitHiddenAt` as the old breakpoint behavior.

### Task 2: Implement the minimal A1 CSS payload

**Files:**
- Modify: `skin-package/shared/injector.mjs:350-360`

- [ ] **Step 1: Return the CSS contract fields in the payload report**

Extend `validateRendererPayload`'s returned object with:

```js
rendererCss: buildRendererCss(rendererPayload(payload), "yang-mi-codex-skin"),
portraitHiddenAt: null,
```

- [ ] **Step 2: Replace only the portrait and veil CSS**

Keep the chrome tint and exact two-node markup unchanged. Change the generated styles to:

```css
#yang-mi-codex-skin .ym-veil {
  position:absolute; inset:0;
  background:linear-gradient(180deg,${data.theme.surface}b8 0,${data.theme.surface}2b 72px,transparent 150px);
  box-shadow:inset 0 0 0 1px ${data.theme.accent}30;
}
#yang-mi-codex-skin .ym-portrait {
  position:absolute; right:0; top:0;
  width:min(62vw,820px); height:100%;
  background:linear-gradient(90deg,${data.theme.surface} 0,${data.theme.surface}b8 16%,${data.theme.surface}28 42%,transparent 70%),url("${data.hero}") right center/auto 100% no-repeat;
  opacity:.82; filter:saturate(.86) contrast(1.02);
}
```

Remove the old breakpoint that hides the portrait. Preserve `pointer-events:none`, `aria-hidden`, and the existing fingerprint calculation.

- [ ] **Step 3: Run the focused test and confirm GREEN**

```powershell
node .\tests\test-renderer-payload.mjs
```

Expected result: `PASS: renderer payload contains only the restrained woodland layers.`

### Task 3: Run the full regression suite

**Files:**
- Test: `skin-package/tests/test-*.mjs`
- Test: `skin-package/tests/test-*.ps1`

- [ ] **Step 1: Run all 11 tests serially**

Run the three PowerShell contracts and eight Node tests listed in the existing test directory. Expected result: all tests pass with no renderer structure, payload rejection, readiness, watcher, or autostart regressions.

### Task 4: Synchronize and live-verify the installed skill

**Files:**
- Source: `skin-package/shared/injector.mjs`
- Installed: `C:\Users\Administrator\.codex\skills\yang-mi-codex-skins\shared\injector.mjs`

- [ ] **Step 1: Copy the tested injector to the installed skill**

Copy only the injector source; do not modify WindowsApps, `app.asar`, or Codex files.

- [ ] **Step 2: Reapply the selected theme**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Users\Administrator\.codex\skills\yang-mi-codex-skins\windows\apply-yang-mi-skin.ps1 -ThemeId woodland-white -RestartExisting
```

- [ ] **Step 3: Verify live renderer and persistence state**

Run the installed `verify-yang-mi-skin.ps1` and confirm `pass=true`, theme `woodland-white`, verified watcher/injector identities, loopback port ownership, and the HKCU Run backend.

### Task 5: Visual and interaction verification

- [ ] **Step 1: Inspect a fresh Codex screenshot**

Confirm Yang Mi is clearly visible on the right, the left work area is readable, and no full-window pink haze or replacement controls remain.

- [ ] **Step 2: Confirm native interaction**

Confirm the composer remains editable and the decorative layer remains `pointer-events:none` and `aria-hidden=true`.

- [ ] **Step 3: Record residual manual check**

Ask the user to close and reopen Codex normally once more if a live desktop restart is required; do not claim persistence until the watcher state and renderer verification are fresh.
