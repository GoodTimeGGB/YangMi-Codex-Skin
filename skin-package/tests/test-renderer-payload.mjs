import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const injector = fileURLToPath(new URL("../shared/injector.mjs", import.meta.url));
const result = spawnSync(process.execPath, [
  injector,
  "--theme",
  "woodland-white",
  "--check-payload",
], { encoding: "utf8" });

assert.equal(result.status, 0, result.stderr || result.stdout);
const report = JSON.parse(result.stdout);
assert.equal(report.pass, true);
assert.equal(report.backgroundSource, "custom");
assert.ok(report.heroBytes > 1_000);
assert.ok(report.rendererBytes > report.heroBytes);
assert.deepEqual(report.visualNodes, ["ym-portrait"]);
assert.equal(report.heroReferences, 1);
assert.equal(report.polaroidReferences, 0);
assert.match(report.rendererCss, /right:0/);
assert.match(report.rendererCss, /\.app-shell-main-content-frame\{background-color:transparent!important\}/);
assert.match(report.rendererCss, /\.ym-portrait\{[^}]*left:var\(--ym-workspace-left\);right:0/);
assert.doesNotMatch(report.rendererCss, /left:clamp\(520px,44vw,760px\)/);
assert.match(report.rendererCss, /top:0;bottom:0/);
assert.match(report.rendererCss, /background-size:contain/);
assert.match(report.rendererCss, /background-repeat:no-repeat/);
assert.match(report.rendererCss, /background-position:center/);
assert.doesNotMatch(report.rendererCss, /--ym-output-rail-width/);
assert.doesNotMatch(report.rendererCss, /(?:-webkit-)?mask-image:/);
assert.doesNotMatch(report.rendererCss, /clip-path:/);
assert.doesNotMatch(report.rendererCss, /background-size:cover/);
assert.doesNotMatch(report.rendererCss, /ym-veil/);
assert.doesNotMatch(report.rendererCss, /height:clamp\(160px,28vh,310px\)/);
assert.doesNotMatch(report.rendererCss, /linear-gradient\(90deg/);
assert.doesNotMatch(report.rendererCss, /width:min\(62vw,820px\)|opacity:\.82|\/auto 100%/);
assert.match(report.rendererCss, /body>:not\(\#yang-mi-codex-skin\)\{position:relative;z-index:1\}/);
assert.match(report.rendererCss, /pointer-events:none/);
assert.equal(report.portraitHiddenAt, null);

console.log("PASS: renderer payload contains the right-workspace wallpaper layers.");
