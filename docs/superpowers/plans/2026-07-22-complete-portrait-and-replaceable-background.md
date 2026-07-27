# Complete Portrait and Replaceable Background Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render the entire selected portrait in the right workspace, leave a neutral pet area, and load a user-replaceable background file.

**Architecture:** `buildPayload` resolves one validated custom JPEG before falling back to the selected theme's hero. The existing two-node non-interactive renderer remains intact: its portrait is bounded to the workspace with `contain`, and its veil becomes the neutral lower-right pet clear zone.

**Tech Stack:** Node.js ESM, PowerShell, Node assert, Electron CDP.

---

### Task 1: Add custom background resolution

**Files:**
- Create: `skin-package/assets/custom-background/background.jpg`
- Modify: `skin-package/shared/injector.mjs`
- Modify: `skin-package/tests/test-renderer-payload.mjs`

- [ ] **Step 1: Write failing payload assertions**

Assert that the custom file is reported as the selected background, and that its data URL is the embedded hero when present.

```js
assert.equal(report.backgroundSource, "custom");
assert.match(report.rendererCss, /background-size:contain/);
```

- [ ] **Step 2: Run the payload test**

Run: `node skin-package/tests/test-renderer-payload.mjs`

Expected: FAIL because `backgroundSource` is absent and the renderer uses `cover`.

- [ ] **Step 3: Implement fixed-path selection**

Resolve `assets/custom-background/background.jpg` with `fs.access`; use it when readable, otherwise use `theme.hero`. Preserve the existing JPEG/WebP data-image validation.

- [ ] **Step 4: Run the payload test**

Run: `node skin-package/tests/test-renderer-payload.mjs`

Expected: PASS.

### Task 2: Render a complete portrait and pet clear zone

**Files:**
- Modify: `skin-package/shared/injector.mjs`
- Modify: `skin-package/tests/test-renderer-payload.mjs`

- [ ] **Step 1: Write failing CSS assertions**

Require a workspace-bounded `ym-portrait` with `background-size:contain` and a lower-right `ym-veil` clear zone.

```js
assert.match(report.rendererCss, /\.ym-portrait\{[^}]*left:var\(--ym-workspace-left\)/);
assert.match(report.rendererCss, /background-size:contain/);
assert.match(report.rendererCss, /\.ym-veil\{[^}]*right:0[^}]*bottom:0/);
```

- [ ] **Step 2: Run the payload test**

Run: `node skin-package/tests/test-renderer-payload.mjs`

Expected: FAIL because the existing picture begins at `left:0`, uses `cover`, and the veil is a left transition strip.

- [ ] **Step 3: Implement the two-node CSS change**

Set `--ym-workspace-left` to the left panel width, bound `ym-portrait` to that edge, use `contain center`, apply muted image filters, and reposition `ym-veil` as a non-interactive right-bottom surface block behind the pet.

- [ ] **Step 4: Run renderer tests**

Run: `node skin-package/tests/test-renderer-payload.mjs; node skin-package/tests/test-renderer-structure.mjs`

Expected: both PASS.

### Task 3: Package and verify

**Files:**
- Modify: `C:/Users/Administrator/.codex/skills/yang-mi-codex-skins/shared/injector.mjs`
- Create: `C:/Users/Administrator/.codex/skills/yang-mi-codex-skins/assets/custom-background/background.jpg`
- Modify: `C:/Users/Administrator/.codex/skills/yang-mi-codex-skins/tests/test-renderer-payload.mjs`

- [ ] **Step 1: Run every package test**

Run all `skin-package/tests/test-*.ps1` and `skin-package/tests/test-*.mjs` files in sorted order. Stop on a non-zero exit.

- [ ] **Step 2: Copy verified changed files**

Synchronize the injector, renderer test, and default custom image to the installed skill directory.

- [ ] **Step 3: Run every installed test**

Run all installed `tests/test-*.ps1` and `tests/test-*.mjs` files in sorted order.

- [ ] **Step 4: Refresh manually and verify live state**

The user manually runs `Apply-白衣林间.cmd`, then run installed `injector.mjs --verify` on the verified loopback CDP identity.
