import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const injector = fileURLToPath(new URL("../shared/injector.mjs", import.meta.url));
const result = spawnSync(process.execPath, [injector, "--self-test"], {
  encoding: "utf8",
});

assert.equal(result.status, 0, result.stderr || result.stdout);
const report = JSON.parse(result.stdout);
assert.deepEqual(report, {
  pass: true,
  fixtures: 9,
});

console.log("PASS: readiness self-test rejects splash-only targets.");
