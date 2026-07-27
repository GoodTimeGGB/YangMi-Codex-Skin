# Launcher Race and Pet Overlay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent a transient first renderer verification from surfacing as a launcher error and remove the pet background block.

**Architecture:** The PowerShell launcher treats the exact renderer check as advisory once its watch injector is started, allowing the existing watcher to converge. The existing `ym-veil` node remains for renderer structure compatibility but is hidden, so it cannot paint behind the official transparent pet.

**Tech Stack:** Node.js ESM, PowerShell, Node assert.

---

### Task 1: Lock down nonfatal first verification and transparent pet area

**Files:**
- Modify: `skin-package/tests/test-launcher-readiness-contract.ps1`
- Modify: `skin-package/tests/test-renderer-payload.mjs`

- [ ] **Step 1: Write failing assertions**

```powershell
Assert-True ($source -match '\$verificationPending\s*=\s*-not\s+\$verificationPassed') 'Launcher must preserve a nonfatal pending state.'
Assert-False ($source -match 'Theme verification failed before the deadline') 'Launcher must not emit a transient verification failure.'
```

```js
assert.match(report.rendererCss, /\.ym-veil\{[^}]*display:none/);
assert.doesNotMatch(report.rendererCss, /height:clamp\(160px,28vh,310px\)/);
```

- [ ] **Step 2: Verify RED**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File skin-package/tests/test-launcher-readiness-contract.ps1; node skin-package/tests/test-renderer-payload.mjs`

Expected: both fail because the launcher retains the terminal throw and the veil paints a white block.

- [ ] **Step 3: Implement the minimal changes**

Set `verificationPending` from the verification result alone, remove the terminal stop-and-throw branch, and use `display:none` for `ym-veil`.

- [ ] **Step 4: Verify GREEN**

Run: same command as Step 2.

Expected: both pass.

### Task 2: Validate and install

**Files:**
- Modify: `C:/Users/Administrator/.codex/skills/yang-mi-codex-skins/windows/apply-yang-mi-skin.ps1`
- Modify: `C:/Users/Administrator/.codex/skills/yang-mi-codex-skins/shared/injector.mjs`
- Modify: installed matching test files

- [ ] **Step 1: Run the complete package suite**

Run all `skin-package/tests/test-*.ps1` and `skin-package/tests/test-*.mjs` files in sorted order.

- [ ] **Step 2: Synchronize verified files**

Copy the launcher, injector, and two updated tests into the installed skill directory.

- [ ] **Step 3: Run the complete installed suite**

Run all installed `tests/test-*.ps1` and `tests/test-*.mjs` files in sorted order.

- [ ] **Step 4: Refresh manually and verify CDP state**

The user runs `Apply-白衣林间.cmd`, then verify the renderer through the installed injector on the verified loopback CDP identity.
