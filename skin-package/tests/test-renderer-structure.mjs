import assert from "node:assert/strict";
import fs from "node:fs";
import * as injector from "../shared/injector.mjs";

const shared = new URL("../shared/", import.meta.url);
const sharedFiles = fs.readdirSync(shared).filter((file) => /\.(?:js|mjs)$/.test(file));
assert.deepEqual(sharedFiles, ["injector.mjs"]);
const sources = sharedFiles.map((file) => [file, fs.readFileSync(new URL(file, shared), "utf8")]);
for (const legacyMarker of [
  "foregroundRenderer",
  "fullWallpaperRenderer",
  "readableWallpaperRenderer",
  "floralStudioRenderer",
  "roseBannerRenderer",
  "greenBeeWorkspaceRenderer",
  "immersiveGreenBeeWorkspaceRenderer",
]) {
  for (const [file, source] of sources) {
    assert.equal(source.includes(legacyMarker), false, `legacy renderer marker remains in ${file}: ${legacyMarker}`);
  }
}
for (const promotionalContent of ["开始一个新任务", "和 Codex 一起创作", "蜜蜂动态", "绿色应援工作台", "灵感，正在盛放"]) {
  for (const [file, source] of sources) {
    assert.equal(source.includes(promotionalContent), false, `promotional renderer content remains in ${file}: ${promotionalContent}`);
  }
}

assert.equal(typeof injector.buildRenderer, "function");
const payload = await injector.buildPayload("woodland-white");
const script = injector.buildRenderer(payload);
const mutated = script.replace(
  '<div class="ym-portrait"></div>',
  '<div class="ym-portrait"></div><div class="ym-extra"></div>',
);
assert.notEqual(mutated, script);
assert.throws(
  () => injector.validateRendererPayload(payload, mutated),
  /Renderer child structure is not restrained/,
);

const appended = script.replace(
  "document.head.append(style);",
  "layer.append(document.createElement('div')); document.head.append(style);",
);
assert.notEqual(appended, script);
assert.throws(
  () => injector.validateRendererPayload(payload, appended),
  /Renderer script does not exactly match the approved renderer/,
);

console.log("PASS: legacy renderers are absent and extra visual nodes are rejected.");
