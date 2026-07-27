# Codex Woodland A1 Visual Revision

## Decision

Adopt the A1 “right-side full-height” composition for the `woodland-white`
theme. Yang Mi is the primary visual signal, while the native Codex work area
remains the primary interaction surface.

## Visual Rules

- Use the existing woodland hero asset at the far right, spanning the usable
  renderer height and approximately 62% of the content canvas width.
- Keep the portrait visibly readable: no blanket opacity below 0.75 and no
  global pink or white haze over the entire window.
- Apply a left-to-right white fade only where the portrait meets the editor;
  text and composer remain legible without tinting the whole workspace.
- Keep the palette cool white, pale woodland green, and muted slate-green.
- Tint only existing Codex chrome surfaces: header, navigation rail, and
  composer focus border. Do not add banners, cards, replacement controls, or
  promotional copy.
- Keep the visual layer `pointer-events: none`, `aria-hidden="true"`, and
  behind native controls.
- Preserve the image on ordinary desktop windows; use a narrower crop rather
  than hiding the subject at common laptop dimensions.

## Injection Contract

The renderer continues to contain exactly two decorative children,
`ym-veil` and `ym-portrait`, with the existing marker and fingerprint checks.
Only the CSS payload for those layers changes. Existing readiness gating,
watch retries, autostart persistence, and safe rollback remain unchanged.

## Verification

- Add a payload regression asserting the A1 CSS declares a readable portrait
  width, visible opacity, right anchoring, and a local transition fade.
- Keep all existing renderer-structure, payload-rejection, readiness, watcher,
  and autostart tests green.
- Apply the installed skill and run live verification against the current
  Codex renderer.
- Confirm the native composer remains editable and the decoration remains
  non-interactive.

## Out Of Scope

No changes to `WindowsApps`, `app.asar`, Codex files, signatures,
authentication, threads, pets, plugins, or the selected autostart mechanism.
