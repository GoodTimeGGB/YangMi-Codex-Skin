# Right Workspace Wallpaper and Launcher Readiness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fill the complete right Codex workspace with the wallpaper and prevent the launcher from failing while the initial renderer target is still loading.

**Architecture:** The renderer remains a non-interactive fixed layer below native application content. Its portrait starts at the window edge so the opaque left navigation masks it while transparent workspace ancestors expose it. The PowerShell launcher continues to use the existing watcher, but treats its first exact-renderer verification as an asynchronous readiness condition instead of a terminal race.

**Tech Stack:** Node.js 22 ESM, PowerShell, Electron CDP, Node assert tests.

---

### Task 1: Cover the full right workspace

**Files:**
- Modify: `skin-package/tests/test-renderer-payload.mjs`
- Modify: `skin-package/shared/injector.mjs`

- [ ] **Step 1: Write the failing CSS contract**

Add assertions requiring the background layer to begin at `left:0`, require workspace-frame transparency, and reject the prior `left:clamp(520px,44vw,760px)` boundary.

```js
assert.match(report.rendererCss, /\.app-shell-main-content-frame\{background-color:transparent!important\}/);
assert.match(report.rendererCss, /\.ym-portrait\{[^}]*left:0;right:0/);
assert.match(report.rendererCss, /\.ym-veil\{[^}]*left:0/);
assert.doesNotMatch(report.rendererCss, /left:clamp\(520px,44vw,760px\)/);
```

- [ ] **Step 2: Verify the test fails**

Run: `node skin-package/tests/test-renderer-payload.mjs`

Expected: assertion failure because the current portrait begins partway into the workspace.

- [ ] **Step 3: Implement the smallest CSS change**

Keep the existing two non-interactive nodes and `cover` crop. Make `main`, `[role="main"]`, and `.app-shell-main-content-frame` transparent, then set both `ym-portrait` and its narrow `ym-veil` transition to `left:0`.

- [ ] **Step 4: Verify the CSS contract passes**

Run: `node skin-package/tests/test-renderer-payload.mjs`

Expected: `PASS: renderer payload contains the right-workspace wallpaper layers.`

### Task 2: Wait for a watcher-driven exact renderer state

**Files:**
- Modify: `skin-package/tests/test-launcher-readiness-contract.ps1`
- Modify: `skin-package/windows/apply-yang-mi-skin.ps1`

- [ ] **Step 1: Write the failing launcher contract**

Create a PowerShell source-contract test that requires the launcher to tolerate an initial non-zero `--verify` exit while the spawned watcher remains alive, retry until the existing deadline, and include the last verification output only after that deadline.

```powershell
Assert-True ($source -match '\$verificationOutput\s*=\s*@\(&\s*\$node\.Path\s+\$injector\s+--verify') 'Launcher must poll the exact renderer verification.'
Assert-True ($source -match 'Start-Sleep -Milliseconds 500') 'Launcher must wait between renderer checks.'
Assert-True ($source -match 'Theme verification failed before the deadline') 'Launcher must retain an actionable terminal diagnostic.'
```

- [ ] **Step 2: Verify the test fails**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File skin-package/tests/test-launcher-readiness-contract.ps1`

Expected: contract failure because the current test does not exist.

- [ ] **Step 3: Implement conservative readiness handling**

Retain the existing 30-second deadline and exact renderer verification. Do not loosen CDP origin, browser identity, or renderer checks. Ensure a completed watcher process is identified before the deadline and its error log is included in the terminal diagnostic; an initial verification miss continues polling while it remains alive.

- [ ] **Step 4: Verify the launcher contract passes**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File skin-package/tests/test-launcher-readiness-contract.ps1`

Expected: `PASS: launcher waits for watcher-driven exact renderer readiness.`

### Task 3: Validate the package and installed skill copy

**Files:**
- Modify: `C:/Users/Administrator/.codex/skills/yang-mi-codex-skins/shared/injector.mjs`
- Modify: `C:/Users/Administrator/.codex/skills/yang-mi-codex-skins/windows/apply-yang-mi-skin.ps1`
- Create: `C:/Users/Administrator/.codex/skills/yang-mi-codex-skins/tests/test-launcher-readiness-contract.ps1`

- [ ] **Step 1: Run the package suite**

Run all `skin-package/tests/test-*.ps1` and `skin-package/tests/test-*.mjs` files in sorted order. Stop on the first non-zero exit.

- [ ] **Step 2: Synchronize only verified changed files**

Copy the tested renderer, launcher, and launcher contract test from `skin-package` to the installed skill directory.

- [ ] **Step 3: Run the same suite from the installed skill directory**

Run all installed `tests/test-*.ps1` and `tests/test-*.mjs` files in sorted order.

- [ ] **Step 4: Verify the live CDP state without restarting Codex**

Run the installed injector in `--verify` mode against port `9447` using the browser identity returned by `http://127.0.0.1:9447/json/version`.

Expected: JSON report with `pass:true`, an exact renderer state, and no Codex restart.
