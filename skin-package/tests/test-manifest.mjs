import assert from "node:assert/strict";
import fs from "node:fs";
import { buildPayload } from "../shared/injector.mjs";

const root = new URL("../", import.meta.url);
const themes = JSON.parse(fs.readFileSync(new URL("themes.json", root), "utf8"));

assert.equal(themes.version, 1);
assert.deepEqual(themes.themes.map((theme) => theme.id), [
  "floral-retro", "woodland-white", "bridal-moonlight", "noir-silver",
]);
const woodland = themes.themes.find((theme) => theme.id === "woodland-white");
assert.deepEqual(
  { accent: woodland.accent, surface: woodland.surface, ink: woodland.ink },
  { accent: "#879985", surface: "#fbfcfb", ink: "#36413a" },
);
for (const theme of themes.themes) {
  assert.match(theme.label, /.+/);
  assert.match(theme.hero, /^assets\/themes\/[a-z-]+\/hero\.(jpg|webp)$/);
  assert.match(theme.polaroid, /^assets\/themes\/[a-z-]+\/polaroid\.(jpg|webp)$/);
}

for (const theme of themes.themes) {
  const payload = await buildPayload(theme.id);
  assert.equal(payload.theme.id, theme.id);
  assert.match(payload.hero, /^data:image\/(jpeg|webp);base64,/);
  assert.match(payload.polaroid, /^data:image\/(jpeg|webp);base64,/);
  assert.equal(payload.hero.includes("undefined"), false);
  assert.equal(payload.polaroid.includes("undefined"), false);
}

console.log("PASS: four Yang Mi theme records are valid.");
