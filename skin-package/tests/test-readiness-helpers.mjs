import assert from "node:assert/strict";
import * as injector from "../shared/injector.mjs";

assert.equal(typeof injector.anyVisible, "function");
assert.equal(injector.anyVisible([false, true]), true);

assert.equal(typeof injector.isEditableComposerCandidate, "function");
assert.equal(injector.isEditableComposerCandidate({ kind: "textarea", visible: true }), true);
assert.equal(injector.isEditableComposerCandidate({ kind: "textarea", visible: true, readOnly: true }), false);
assert.equal(injector.isEditableComposerCandidate({ kind: "textarea", visible: true, disabled: true }), false);
assert.equal(injector.isEditableComposerCandidate({ kind: "textarea", visible: false }), false);
assert.equal(injector.isEditableComposerCandidate({ kind: "contenteditable", visible: true, contentEditable: "true" }), true);
assert.equal(injector.isEditableComposerCandidate({ kind: "contenteditable", visible: true, contentEditable: "plaintext-only" }), true);
assert.equal(injector.isEditableComposerCandidate({ kind: "contenteditable", visible: true, contentEditable: "false" }), false);
assert.equal(injector.isEditableComposerCandidate({ kind: "contenteditable", visible: true, contentEditable: "true", ariaDisabled: "true" }), false);
assert.equal(injector.isEditableComposerCandidate({ kind: "contenteditable", visible: true, contentEditable: "true", readOnly: true }), false);
assert.equal(injector.isEditableComposerCandidate({ kind: "contenteditable", visible: true, contentEditable: "true", disabled: true }), false);

assert.equal(typeof injector.shouldProcessTarget, "function");
assert.equal(injector.shouldProcessTarget("remove", { app: true, shell: false }), true);
assert.equal(injector.shouldProcessTarget("once", { app: true, shell: false }), false);
assert.equal(injector.shouldProcessTarget("remove", { app: false, shell: true }), false);

console.log("PASS: readiness helpers scan all candidates and reject non-editable composers.");
