# Codex Woodland Skin Design

## Goal

Replace the current large green homepage composition with a restrained
white-and-pale-green Codex skin. The skin must load only after the real Codex
shell is ready and must automatically restore after Windows or Codex restarts.

## Current Root Cause

The existing Yang Mi injector accepts any `app://` target whose document body
exists. Codex creates that target during its transient splash state, so the
skin can appear before the usable application. The injector is launched only
by the manual launcher; no Windows startup mechanism recreates it after Codex
exits or the machine restarts.

## Visual Design

- Palette: cool white surfaces, pale woodland green borders, muted slate-green
  text, and a small warm-gray highlight for focus states.
- Chrome only: tint the header, left navigation, and composer. Do not create a
  banner, task cards, status panel, promotional copy, or layout padding in the
  working area.
- Portrait: a single low-opacity image anchored to the far right. It is hidden
  at narrower window widths and never intercepts pointer input.
- Controls: retain Codex's native structure and interaction. Decorations use
  CSS and non-interactive renderer nodes only.

## Injection And Recovery

1. A Windows Scheduled Task starts a small watcher at interactive user logon.
2. The watcher waits for Codex and a verified loopback-only CDP endpoint. If a
   normal Codex launch has no endpoint, it may take over only during a short,
   bounded startup window after proving every matching process is newly
   started and the usable shell is not ready. Established sessions are never
   restarted automatically.
3. The renderer probe waits for a stable Codex shell region and an editable
   composer or an established main shell container. A bare document body is
   insufficient.
4. The watcher injects the skin after the readiness probe succeeds, and checks
   the marker periodically so navigation and renderer reloads receive the skin
   again.
5. Persistent settings record whether the skin is enabled, the selected theme,
   and preferred port. Separate runtime state records verified executable,
   watcher, injector, port, and browser identities. Restore removes the
   scheduled task, state, and injected marker without modifying Codex files.

## Failure Handling

- If Codex is not running, the watcher remains idle and does not display UI.
- Closing Codex intentionally leaves it closed. The watcher only reacts to a
  later user-initiated launch.
- If startup fails or the shell selectors change after an update, the skin is
  skipped and Codex remains usable without an overlay.
- A stale watcher PID is identity-checked before it is stopped.
- All debugging endpoints remain loopback-only.

## Verification

- The payload parser and renderer readiness probe are tested without Codex.
- A live verification confirms the marker appears only on a ready shell.
- Closing and reopening Codex restores the skin without using the launcher.
- Reboot/login recovery is verified by inspecting the scheduled task and its
  watcher state; a live restart test is run only after saving active drafts.
- The composer remains editable and the right-side artwork stays outside its
  hit-testing and text area.

## Scope

This design uses the existing Yang Mi skin's loopback CDP approach and does
not modify `WindowsApps`, `app.asar`, application signatures, authentication,
threads, or plugins.
