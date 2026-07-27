import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { fileURLToPath } from "node:url";

const injector = fileURLToPath(new URL("../shared/injector.mjs", import.meta.url));
const child = spawn(process.execPath, [
  injector,
  "--watch",
  "--theme",
  "woodland-white",
  "--port",
  "65534",
  "--browser-id",
  "unavailable-test-browser",
], {
  stdio: ["ignore", "ignore", "pipe"],
});

let stderr = "";
child.stderr.setEncoding("utf8");
child.stderr.on("data", (chunk) => { stderr += chunk; });

try {
  await new Promise((resolve) => setTimeout(resolve, 900));
  assert.equal(child.exitCode, null, `watch mode exited instead of retrying: ${stderr}`);
} finally {
  if (child.exitCode === null) child.kill();
  if (child.exitCode === null) await once(child, "exit");
}

console.log("PASS: watch mode survives a transient unavailable Codex endpoint.");
