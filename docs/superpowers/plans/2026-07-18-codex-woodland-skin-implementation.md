# Codex Woodland Skin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the white-and-pale-green Yang Mi Codex skin load only after a usable Codex shell is ready and restore automatically after Windows/Codex restarts.

**Architecture:** A logon Scheduled Task starts a non-interactive PowerShell watcher. The watcher joins a loopback-only Codex CDP session or safely takes over only a newly launched, not-yet-ready Codex process, then waits for a renderer readiness predicate and starts the Node injector in watch mode. The injector applies a small, non-interactive chrome layer and no longer creates homepage content or shifts Codex layout.

**Tech Stack:** PowerShell Scheduled Tasks, Node.js 22+, loopback Chrome DevTools Protocol, existing Yang Mi skin assets.

---

## File Structure

- `C:/Users/Administrator/.codex/skills/yang-mi-codex-skins/shared/injector.mjs`: readiness predicate, idempotent woodland renderer, live verification, and test mode.
- `C:/Users/Administrator/.codex/skills/yang-mi-codex-skins/windows/watch-yang-mi-skin.ps1`: idle background process that discovers Codex and starts the injector only for verified loopback sessions.
- `C:/Users/Administrator/.codex/skills/yang-mi-codex-skins/windows/common-yang-mi-skin.ps1`: strict settings/session IO and watcher/injector identity checks.
- `C:/Users/Administrator/.codex/skills/yang-mi-codex-skins/windows/install-yang-mi-autostart.ps1`: creates or updates the per-user logon task.
- `C:/Users/Administrator/.codex/skills/yang-mi-codex-skins/windows/uninstall-yang-mi-autostart.ps1`: removes the task and safely stops recorded watcher/injector processes.
- `C:/Users/Administrator/.codex/skills/yang-mi-codex-skins/windows/apply-yang-mi-skin.ps1`: records the selected theme and enables the watcher after a successful manual apply.
- `C:/Users/Administrator/.codex/skills/yang-mi-codex-skins/windows/verify-yang-mi-skin.ps1`: reports both renderer and autostart status.

### Task 1: Add A Ready-Shell Regression Check

**Files:**
- Modify: `C:/Users/Administrator/.codex/skills/yang-mi-codex-skins/shared/injector.mjs`

- [ ] **Step 1: Add a deterministic `--self-test` mode before changing live injection.**

  The mode evaluates the pure readiness predicate against fixture-like objects:

  ```js
  const cases = [
    [{ readyState: "complete", body: true, shell: false, composer: false }, false],
    [{ readyState: "complete", body: true, shell: true, composer: false }, true],
    [{ readyState: "interactive", body: true, shell: false, composer: true }, true],
  ];
  for (const [input, expected] of cases) {
    if (isCodexShellReady(input) !== expected) throw new Error("readiness self-test failed");
  }
  console.log(JSON.stringify({ pass: true, test: "shell-readiness" }));
  ```

- [ ] **Step 2: Run the new test before implementing the predicate.**

  Run: `node C:/Users/Administrator/.codex/skills/yang-mi-codex-skins/shared/injector.mjs --self-test`

  Expected: fail because `isCodexShellReady` is not implemented.

- [ ] **Step 3: Implement `isCodexShellReady` and use it in the CDP probe.**

  The browser-side probe must require `document.readyState !== "loading"`, a body, and either a visible `main`/application shell region or an editable composer. It must reject splash-only pages. The CDP return must be a compact record:

  ```js
  { app: location.protocol === "app:", ready: isCodexShellReady(snapshot), skin: window.__YANG_MI_CODEX_SKIN__ ?? null }
  ```

- [ ] **Step 4: Re-run the self-test.**

  Run: `node C:/Users/Administrator/.codex/skills/yang-mi-codex-skins/shared/injector.mjs --self-test`

  Expected: JSON containing `"pass":true` and `"test":"shell-readiness"`.

### Task 2: Replace The Homepage Overlay With Woodland Chrome

**Files:**
- Modify: `C:/Users/Administrator/.codex/skills/yang-mi-codex-skins/shared/injector.mjs`

- [ ] **Step 1: Add a renderer self-test assertion that the payload contains no homepage layout mutations.**

  The assertion must reject these strings in the final rendered payload: `ym-actions`, `ym-status`, `padding-top:394px`, and `ym-banner`.

- [ ] **Step 2: Run the payload check and observe it fail on the current renderer.**

  Run: `node C:/Users/Administrator/.codex/skills/yang-mi-codex-skins/shared/injector.mjs --check-payload --theme woodland-white`

  Expected: fail with a forbidden homepage marker.

- [ ] **Step 3: Replace the final `renderer` assignment with an idempotent woodland-only renderer.**

  The produced layer must contain exactly `ym-veil` and `ym-portrait`; it must use `pointer-events:none`, be hidden at widths below `1180px`, and apply only scoped styles:

  ```css
  html[data-yang-mi-skin] .app-header-tint { background:#f7fbf6 !important; }
  html[data-yang-mi-skin] .app-shell-left-panel { background:#f3f8f1 !important; }
  html[data-yang-mi-skin] textarea { border-color:#b9cfb5 !important; }
  ```

  It must not set main-surface padding, create text content, or alter native buttons' event behavior.

- [ ] **Step 4: Run the payload check.**

  Run: `node C:/Users/Administrator/.codex/skills/yang-mi-codex-skins/shared/injector.mjs --check-payload --theme woodland-white`

  Expected: JSON with `"pass":true`, no forbidden homepage markers, and nonzero image byte counts.

### Task 3: Implement The Auto-Recovery Watcher

**Files:**
- Create: `C:/Users/Administrator/.codex/skills/yang-mi-codex-skins/windows/watch-yang-mi-skin.ps1`
- Modify: `C:/Users/Administrator/.codex/skills/yang-mi-codex-skins/windows/apply-yang-mi-skin.ps1`

- [ ] **Step 1: Add a `-WhatIf` path to the watcher and assert it performs no process starts.**

  The dry path prints `watcher-ready` after resolving its paths, selected `themeId`, and saved state, without opening CDP or launching Node.

- [ ] **Step 2: Run the watcher dry path before the watcher exists.**

  Run: `powershell -ExecutionPolicy Bypass -File C:/Users/Administrator/.codex/skills/yang-mi-codex-skins/windows/watch-yang-mi-skin.ps1 -WhatIf`

  Expected: file-not-found failure.

- [ ] **Step 3: Create the watcher.**

  It must read persistent `settings.json` and volatile `session.json`, remain
  idle while Codex is absent, and invoke the existing verified install/CDP
  helpers. When a user launches Codex normally, it may restart it with
  `--remote-debugging-address=127.0.0.1` only if all matching processes are
  within a bounded startup age and the usable shell is not ready; otherwise it
  records a blocked reason and leaves the session untouched. It starts one
  hidden Node injector with `--watch` and records PID plus start time. Stale
  processes are stopped only after matching executable, script, arguments,
  port, browser identity, and start time.

- [ ] **Step 4: Run the watcher dry path.**

  Run: `powershell -ExecutionPolicy Bypass -File C:/Users/Administrator/.codex/skills/yang-mi-codex-skins/windows/watch-yang-mi-skin.ps1 -WhatIf`

  Expected: `watcher-ready` and no new Node process.

- [ ] **Step 5: Update manual apply to start/restart the watcher instead of leaving a one-off injector as the only recovery mechanism.**

  Manual apply continues to validate the theme payload and verifies the live injection, then launches the watcher hidden and persists its identity.

### Task 4: Install And Remove The Logon Task

**Files:**
- Create: `C:/Users/Administrator/.codex/skills/yang-mi-codex-skins/windows/install-yang-mi-autostart.ps1`
- Create: `C:/Users/Administrator/.codex/skills/yang-mi-codex-skins/windows/uninstall-yang-mi-autostart.ps1`
- Modify: `C:/Users/Administrator/.codex/skills/yang-mi-codex-skins/windows/apply-yang-mi-skin.ps1`
- Modify: `C:/Users/Administrator/.codex/skills/yang-mi-codex-skins/windows/restore-yang-mi-skin.ps1`

- [ ] **Step 1: Add the installer `-WhatIf` test path.**

  It must report task name `YangMiCodexSkinWatcher` and the exact watcher command without registering it.

- [ ] **Step 2: Implement the installer.**

  Register a per-user task with `New-ScheduledTaskAction`, a logon trigger for the current user, `StartWhenAvailable`, and hidden PowerShell execution. Do not request elevation and do not run at system boot.

- [ ] **Step 3: Implement uninstall and wire restore to call it.**

  Uninstall must disable/unregister only `YangMiCodexSkinWatcher`, stop only identity-matched watcher/injector processes, then remove Yang Mi skin state.

- [ ] **Step 4: Register and inspect the task.**

  Run: `powershell -ExecutionPolicy Bypass -File C:/Users/Administrator/.codex/skills/yang-mi-codex-skins/windows/install-yang-mi-autostart.ps1`

  Run: `Get-ScheduledTask -TaskName YangMiCodexSkinWatcher | Select-Object TaskName,State`

  Expected: task exists and is ready or running.

### Task 5: Verify The Live Contract

**Files:**
- Modify: `C:/Users/Administrator/.codex/skills/yang-mi-codex-skins/windows/verify-yang-mi-skin.ps1`

- [ ] **Step 1: Extend verification to require the scheduled task and watcher identity.**

  The script must return nonzero when the marker is missing, theme differs, the task is absent, or its recorded watcher cannot be identity-verified.

- [ ] **Step 2: Run verification with the skin active.**

  Run: `powershell -ExecutionPolicy Bypass -File C:/Users/Administrator/.codex/skills/yang-mi-codex-skins/windows/verify-yang-mi-skin.ps1`

  Expected: zero exit code and JSON/object output naming `woodland-white`, `YangMiCodexSkinWatcher`, and a live injector.

- [ ] **Step 3: Capture a live screenshot and confirm the interaction boundary.**

  Run the injector's verify/screenshot command against the verified loopback endpoint, inspect the capture at desktop width, and confirm: no homepage cards/banner, portrait confined to right edge, composer visible, and no overlay element receives pointer input.

- [ ] **Step 4: Test recovery by closing Codex, waiting for the watcher to observe exit, and opening Codex again.**

  Expected: the marker is absent while Codex is closed, then appears only after the ready shell probe passes on the new process. Re-run the verification command.

## Plan Self-Review

- Spec coverage: Tasks 1 and 5 cover delayed injection; Task 2 covers the cold-white/green visual surface; Tasks 3 and 4 cover restart recovery; Task 5 covers functional safety and validation.
- No-placeholder scan: no open requirements remain. Windows reboot is not forced automatically because it would disrupt the user; task registration plus a close/open recovery test is the safe in-session proxy.
- Type consistency: persisted values are `themeId`, `port`, `browserId`, `injectorPid`, `watcherPid`, and their start times; all scripts use the same task name, `YangMiCodexSkinWatcher`.
