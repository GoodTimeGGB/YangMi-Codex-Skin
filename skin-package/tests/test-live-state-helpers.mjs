import assert from "node:assert/strict";
import * as injector from "../shared/injector.mjs";

assert.equal(typeof injector.isExactRendererState, "function");
assert.equal(typeof injector.allTargetsCleaned, "function");
assert.equal(typeof injector.isCodexWorkspaceTarget, "function");

assert.equal(injector.isCodexWorkspaceTarget({ url: "app://-/index.html" }), true);
assert.equal(injector.isCodexWorkspaceTarget({ url: "app://-/index.html?initialRoute=%2Favatar-overlay" }), false);
assert.equal(injector.isCodexWorkspaceTarget({ url: "app://-/index.html?initialRoute=/avatar-overlay" }), false);
assert.equal(injector.isCodexWorkspaceTarget({ url: "https://example.test/" }), false);

const expectedFingerprint = "7f3a21c9";
const exact = {
  skin: { version: injector.VERSION, theme: "woodland-white" },
  renderer: {
    layerCount: 1,
    styleCount: 1,
    childClasses: ["ym-portrait"],
    ariaHidden: "true",
    layerPointerEvents: "none",
    computedPointerEvents: "none",
    styleVersion: injector.VERSION,
    styleDeclaredFingerprint: expectedFingerprint,
    styleComputedFingerprint: expectedFingerprint,
    styleTextLength: 128,
  },
};

assert.equal(injector.isExactRendererState(exact, "woodland-white", expectedFingerprint), true);
for (const renderer of [
  { ...exact.renderer, layerCount: 2 },
  { ...exact.renderer, styleCount: 2 },
  { ...exact.renderer, childClasses: ["ym-veil"] },
  { ...exact.renderer, childClasses: ["ym-portrait", "ym-extra"] },
  { ...exact.renderer, ariaHidden: "false" },
  { ...exact.renderer, layerPointerEvents: "auto" },
  { ...exact.renderer, computedPointerEvents: "auto" },
]) {
  assert.equal(injector.isExactRendererState({ ...exact, renderer }, "woodland-white", expectedFingerprint), false);
}
assert.equal(injector.isExactRendererState({ ...exact, renderer: { ...exact.renderer, styleTextLength: 0 } }, "woodland-white", expectedFingerprint), false);
assert.equal(injector.isExactRendererState({ ...exact, renderer: { ...exact.renderer, styleVersion: "stale", styleDeclaredFingerprint: "15aa30c4", styleComputedFingerprint: "15aa30c4" } }, "woodland-white", expectedFingerprint), false);
assert.equal(injector.isExactRendererState({ ...exact, renderer: { ...exact.renderer, styleComputedFingerprint: "098c712e" } }, "woodland-white", expectedFingerprint), false);
assert.equal(injector.isExactRendererState({ ...exact, skin: { version: injector.VERSION, theme: "spoof" } }, "woodland-white", expectedFingerprint), false);

assert.equal(injector.allTargetsCleaned(2, 2), true);
assert.equal(injector.allTargetsCleaned(2, 1), false);
assert.equal(injector.allTargetsCleaned(0, 0), false);

console.log("PASS: live verification requires one exact renderer and removal requires every target.");
