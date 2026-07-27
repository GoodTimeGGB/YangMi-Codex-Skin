import fs from "node:fs/promises";
import http from "node:http";
import crypto from "node:crypto";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
export const VERSION = "1.1.0";
const hosts = new Set(["127.0.0.1", "localhost", "::1", "[::1]"]);
const safeId = /^[A-Za-z0-9._-]{1,200}$/;

function args(argv) {
  const out = { port: 9447, mode: "once", theme: null, browserId: null, timeout: 30000 };
  for (let i = 0; i < argv.length; i++) {
    const value = argv[i];
    if (value === "--theme") out.theme = argv[++i];
    else if (value === "--port") out.port = Number(argv[++i]);
    else if (value === "--browser-id") out.browserId = argv[++i];
    else if (value === "--watch") out.mode = "watch";
    else if (value === "--once") out.mode = "once";
    else if (value === "--verify") out.mode = "verify";
    else if (value === "--remove") out.mode = "remove";
    else if (value === "--check-payload") out.mode = "check";
    else if (value === "--self-test") out.mode = "self-test";
    else throw new Error(`Unknown argument: ${value}`);
  }
  if (!Number.isInteger(out.port) || out.port < 1024 || out.port > 65535) throw new Error("Invalid CDP port");
  if (!out.theme && !["remove", "self-test"].includes(out.mode)) throw new Error("--theme is required");
  if (out.browserId !== null && !safeId.test(out.browserId)) throw new Error("Invalid CDP browser identity");
  return out;
}

export async function resolveTheme(id) {
  const manifest = JSON.parse(await fs.readFile(path.join(root, "themes.json"), "utf8"));
  const theme = manifest.themes.find((item) => item.id === id || item.label === id);
  if (!theme) throw new Error(`Unknown Yang Mi theme: ${id}`);
  return theme;
}

export async function buildPayload(id) {
  const theme = await resolveTheme(id);
  const customBackground = path.join(root, "assets", "custom-background", "background.jpg");
  let heroPath = path.join(root, theme.hero);
  let backgroundSource = "theme";
  try {
    await fs.access(customBackground);
    heroPath = customBackground;
    backgroundSource = "custom";
  } catch {}
  const polaroidPath = path.join(root, theme.polaroid);
  const [hero, polaroid] = await Promise.all([fs.readFile(heroPath), fs.readFile(polaroidPath)]);
  const mime = (file) => file.toLowerCase().endsWith(".jpg") ? "image/jpeg" : "image/webp";
  return { theme, hero: `data:${mime(heroPath)};base64,${hero.toString("base64")}`, polaroid: `data:${mime(polaroidPath)};base64,${polaroid.toString("base64")}`, backgroundSource };
}

export function anyVisible(candidates) {
  return Array.isArray(candidates) && candidates.some((candidate) =>
    typeof candidate === "boolean" ? candidate : candidate?.visible === true,
  );
}

export function isEditableComposerCandidate(candidate) {
  if (!candidate || candidate.visible !== true || candidate.readOnly === true || candidate.disabled === true || String(candidate.ariaDisabled).toLowerCase() === "true") return false;
  if (candidate.kind === "textarea") return true;
  if (candidate.kind !== "contenteditable") return false;
  return ["true", "plaintext-only"].includes(String(candidate.contentEditable).toLowerCase());
}

export function isCodexShellReady(snapshot) {
  if (!snapshot || snapshot.readyState === "loading" || snapshot.body !== true) return false;
  const shells = Array.isArray(snapshot.shells) ? snapshot.shells : [snapshot.shell];
  const composers = Array.isArray(snapshot.composers)
    ? snapshot.composers
    : snapshot.composer === true
      ? [{ kind: "textarea", visible: true }]
      : snapshot.composer
        ? [snapshot.composer]
        : [];
  return anyVisible(shells) || composers.some(isEditableComposerCandidate);
}

export function shouldProcessTarget(mode, status) {
  return status?.app === true && (mode === "remove" || (status.ready ?? status.shell) === true);
}

export function isCodexWorkspaceTarget(target) {
  if (typeof target?.url !== "string") return false;
  try {
    const url = new URL(target.url);
    return url.protocol === "app:" && url.pathname === "/index.html" && url.searchParams.get("initialRoute") !== "/avatar-overlay";
  } catch {
    return false;
  }
}

export function isExactRendererState(status, themeId, expectedFingerprint) {
  const renderer = status?.renderer;
  return status?.skin?.version === VERSION
    && status.skin.theme === themeId
    && typeof expectedFingerprint === "string"
    && expectedFingerprint.length > 0
    && renderer?.layerCount === 1
    && renderer.styleCount === 1
    && Array.isArray(renderer.childClasses)
    && renderer.childClasses.length === 1
    && renderer.childClasses[0] === "ym-portrait"
    && renderer.ariaHidden === "true"
    && renderer.layerPointerEvents === "none"
    && renderer.computedPointerEvents === "none"
    && renderer.styleVersion === VERSION
    && renderer.styleTextLength > 0
    && renderer.styleDeclaredFingerprint === expectedFingerprint
    && renderer.styleComputedFingerprint === expectedFingerprint
    && renderer.styleDeclaredFingerprint === renderer.styleComputedFingerprint;
}

export function allTargetsCleaned(targetCount, cleanedCount) {
  return Number.isInteger(targetCount) && targetCount > 0 && cleanedCount === targetCount;
}

const jpegHuffmanSofMarkers = new Set([0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7]);
const jpegArithmeticSofMarkers = new Set([0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf]);
const jpegSofMarkers = new Set([...jpegHuffmanSofMarkers, ...jpegArithmeticSofMarkers]);
const jpegProgressiveSofMarkers = new Set([0xc2, 0xc6, 0xca, 0xce]);

function validateJpegDqt(bytes, start, end) {
  if (start === end) throw new Error("Invalid JPEG structure");
  for (let offset = start; offset < end;) {
    const info = bytes[offset++];
    const tableLength = (info >> 4) === 0 ? 64 : (info >> 4) === 1 ? 128 : 0;
    if ((info & 0x0f) > 3 || !tableLength || offset + tableLength > end) throw new Error("Invalid JPEG structure");
    offset += tableLength;
  }
}

function validateJpegDht(bytes, start, end) {
  if (start === end) throw new Error("Invalid JPEG structure");
  for (let offset = start; offset < end;) {
    const info = bytes[offset++];
    if ((info >> 4) > 1 || (info & 0x0f) > 3 || offset + 16 > end) throw new Error("Invalid JPEG structure");
    let values = 0;
    for (let index = 0; index < 16; index++) values += bytes[offset + index];
    offset += 16;
    if (!values || offset + values > end) throw new Error("Invalid JPEG structure");
    offset += values;
  }
}

function validateJpegDac(bytes, start, end) {
  if ((end - start) === 0 || (end - start) % 2 !== 0) throw new Error("Invalid JPEG structure");
  for (let offset = start; offset < end; offset += 2) {
    if ((bytes[offset] >> 4) > 1 || (bytes[offset] & 0x0f) > 3) throw new Error("Invalid JPEG structure");
  }
}

function findJpegScanEnd(bytes, offset) {
  let hasEntropy = false;
  while (offset < bytes.length) {
    if (bytes[offset++] !== 0xff) { hasEntropy = true; continue; }
    const markerOffset = offset - 1;
    while (offset < bytes.length && bytes[offset] === 0xff) offset++;
    if (offset >= bytes.length) throw new Error("Invalid JPEG structure");
    const marker = bytes[offset++];
    if (marker === 0x00) { hasEntropy = true; continue; }
    if (marker >= 0xd0 && marker <= 0xd7) continue;
    if (!hasEntropy) throw new Error("Invalid JPEG structure");
    return markerOffset;
  }
  throw new Error("Invalid JPEG structure");
}

function validateJpegSos(bytes, offset, segmentEnd, frameComponents, progressive) {
  const scanComponents = bytes[offset + 2];
  if (scanComponents === 0 || scanComponents > frameComponents || segmentEnd !== offset + 6 + 2 * scanComponents) throw new Error("Invalid JPEG structure");
  const spectralStart = bytes[segmentEnd - 3];
  const spectralEnd = bytes[segmentEnd - 2];
  const approximation = bytes[segmentEnd - 1];
  if (!progressive) {
    if (spectralStart !== 0 || spectralEnd !== 63 || approximation !== 0) throw new Error("Invalid JPEG structure");
    return;
  }
  const successiveHigh = approximation >> 4;
  const successiveLow = approximation & 0x0f;
  if (spectralStart > spectralEnd || spectralEnd > 63 || (spectralStart === 0 && spectralEnd !== 0) || (spectralStart !== 0 && scanComponents !== 1) || successiveHigh > 13 || successiveLow > 13 || (successiveHigh !== 0 && successiveHigh !== successiveLow + 1)) {
    throw new Error("Invalid JPEG structure");
  }
}

function validateJpegStructure(bytes) {
  if (bytes.length < 4 || bytes[0] !== 0xff || bytes[1] !== 0xd8) {
    throw new Error("Invalid JPEG structure");
  }
  let offset = 2;
  let hasSof = false;
  let hasSos = false;
  let hasDqt = false;
  let hasDht = false;
  let hasDac = false;
  let codingMode = null;
  let progressive = false;
  let frameComponents = 0;
  while (offset < bytes.length) {
    if (bytes[offset++] !== 0xff) throw new Error("Invalid JPEG structure");
    while (offset < bytes.length && bytes[offset] === 0xff) offset++;
    if (offset >= bytes.length) throw new Error("Invalid JPEG structure");
    const marker = bytes[offset++];
    if (marker === 0xd9) {
      if (!hasSof || !hasSos || offset !== bytes.length) throw new Error("Invalid JPEG structure");
      return;
    }
    if (!marker || marker === 0xd8) throw new Error("Invalid JPEG structure");
    if (marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) throw new Error("Invalid JPEG structure");
    if (offset + 2 > bytes.length) throw new Error("Invalid JPEG structure");
    const segmentLength = bytes.readUInt16BE(offset);
    const segmentEnd = offset + segmentLength;
    if (segmentLength < 2 || segmentEnd > bytes.length) throw new Error("Invalid JPEG structure");
    if (jpegSofMarkers.has(marker)) {
      if (hasSof) throw new Error("Invalid JPEG structure");
      frameComponents = bytes[offset + 7];
      if (segmentLength < 11 || bytes[offset + 2] === 0 || bytes.readUInt16BE(offset + 3) === 0 || bytes.readUInt16BE(offset + 5) === 0 || frameComponents === 0 || segmentLength !== 8 + 3 * frameComponents) {
        throw new Error("Invalid JPEG structure");
      }
      hasSof = true;
      codingMode = jpegHuffmanSofMarkers.has(marker) ? "huffman" : "arithmetic";
      progressive = jpegProgressiveSofMarkers.has(marker);
    } else if (marker === 0xdb) {
      validateJpegDqt(bytes, offset + 2, segmentEnd);
      hasDqt = true;
    } else if (marker === 0xc4) {
      validateJpegDht(bytes, offset + 2, segmentEnd);
      hasDht = true;
    } else if (marker === 0xcc) {
      validateJpegDac(bytes, offset + 2, segmentEnd);
      hasDac = true;
    } else if (marker !== 0xdd && marker !== 0xfe && (marker < 0xe0 || marker > 0xef) && marker !== 0xda) {
      throw new Error("Invalid JPEG structure");
    }
    if (marker === 0xda) {
      if (!hasSof || !hasDqt || (codingMode === "huffman" ? !hasDht : !hasDac)) throw new Error("Invalid JPEG structure");
      validateJpegSos(bytes, offset, segmentEnd, frameComponents, progressive);
      hasSos = true;
      offset = findJpegScanEnd(bytes, segmentEnd);
      continue;
    }
    offset = segmentEnd;
  }
  throw new Error("Invalid JPEG structure");
}

function validateWebpStructure(bytes) {
  if (bytes.length < 20 || bytes.toString("ascii", 0, 4) !== "RIFF" || bytes.toString("ascii", 8, 12) !== "WEBP" || bytes.readUInt32LE(4) !== bytes.length - 8) {
    throw new Error("Invalid WebP structure");
  }
  let offset = 12;
  let hasImageChunk = false;
  while (offset < bytes.length) {
    if (offset + 8 > bytes.length) throw new Error("Invalid WebP structure");
    const fourcc = bytes.toString("ascii", offset, offset + 4);
    const chunkSize = bytes.readUInt32LE(offset + 4);
    const chunkEnd = offset + 8 + chunkSize;
    const paddedEnd = chunkEnd + (chunkSize & 1);
    if (chunkEnd > bytes.length || paddedEnd > bytes.length) throw new Error("Invalid WebP structure");
    const data = offset + 8;
    if (fourcc === "VP8 ") {
      if (hasImageChunk || chunkSize < 10 || (bytes[data] & 1) !== 0 || bytes[data + 3] !== 0x9d || bytes[data + 4] !== 0x01 || bytes[data + 5] !== 0x2a || (bytes.readUInt16LE(data + 6) & 0x3fff) === 0 || (bytes.readUInt16LE(data + 8) & 0x3fff) === 0) throw new Error("Invalid WebP structure");
      hasImageChunk = true;
    } else if (fourcc === "VP8L") {
      if (hasImageChunk || chunkSize < 5 || bytes[data] !== 0x2f) throw new Error("Invalid WebP structure");
      const header = bytes.readUInt32LE(data + 1);
      if ((header >>> 29) !== 0 || ((header & 0x3fff) + 1) <= 0 || (((header >>> 14) & 0x3fff) + 1) <= 0) throw new Error("Invalid WebP structure");
      hasImageChunk = true;
    }
    offset = paddedEnd;
  }
  if (offset !== bytes.length || !hasImageChunk) throw new Error("Invalid WebP structure");
}

export function decodeDataImage(value) {
  const match = /^data:image\/(jpeg|webp);base64,([A-Za-z0-9+/]+={0,2})$/.exec(value ?? "");
  if (!match || match[2].length % 4 !== 0) throw new Error("Malformed image data URL");
  const bytes = Buffer.from(match[2], "base64");
  if (!bytes.length || bytes.toString("base64") !== match[2]) throw new Error("Malformed image data URL");
  if (match[1] === "jpeg") validateJpegStructure(bytes);
  else validateWebpStructure(bytes);
  if (bytes.length < 1024 || bytes.length > 16 * 1024 * 1024) throw new Error("Decoded image size is outside the allowed range");
  return { mime: `image/${match[1]}`, bytes };
}

function wsUrl(value, port, kind, id) {
  const url = new URL(value);
  if (url.protocol !== "ws:" || !hosts.has(url.hostname) || Number(url.port) !== port || url.username || url.password || url.search || url.hash || url.pathname !== `/devtools/${kind}/${id}`) throw new Error("Rejected a non-loopback CDP endpoint");
  return url.href;
}

async function getTargets(port, browserId) {
  const version = await (await fetch(`http://127.0.0.1:${port}/json/version`, { redirect: "error" })).json();
  const match = new URL(version.webSocketDebuggerUrl).pathname.match(/^\/devtools\/browser\/([A-Za-z0-9._-]{1,200})$/);
  if (!match) throw new Error("Invalid CDP browser endpoint");
  wsUrl(version.webSocketDebuggerUrl, port, "browser", match[1]);
  if (browserId && browserId !== match[1]) throw new Error("CDP browser identity changed");
  const list = await (await fetch(`http://127.0.0.1:${port}/json/list`, { redirect: "error" })).json();
  const pages = list.filter((item) => item?.type === "page" && typeof item.id === "string" && safeId.test(item.id) && String(item.url).startsWith("app://"));
  if (!pages.length) throw new Error("No Codex app page was exposed by CDP");
  pages.forEach((item) => wsUrl(item.webSocketDebuggerUrl, port, "page", item.id));
  return { browserId: match[1], pages };
}

class Cdp {
  constructor(target, port) { this.url = new URL(wsUrl(target.webSocketDebuggerUrl, port, "page", target.id)); this.id = 0; this.pending = new Map(); this.buffer = Buffer.alloc(0); this.socket = null; }
  async open() {
    const key = crypto.randomBytes(16).toString("base64");
    await new Promise((resolve, reject) => {
      const request = http.request({ hostname: this.url.hostname, port: Number(this.url.port), path: this.url.pathname, headers: { Connection: "Upgrade", Upgrade: "websocket", "Sec-WebSocket-Version": "13", "Sec-WebSocket-Key": key } });
      const timer = setTimeout(() => { request.destroy(); reject(new Error("CDP connection timed out")); }, 5000);
      request.once("upgrade", (response, socket, head) => {
        clearTimeout(timer);
        const expected = crypto.createHash("sha1").update(`${key}258EAFA5-E914-47DA-95CA-C5AB0DC85B11`).digest("base64");
        if (response.statusCode !== 101 || response.headers["sec-websocket-accept"] !== expected) { socket.destroy(); reject(new Error("CDP WebSocket handshake was rejected")); return; }
        this.socket = socket; socket.on("data", (chunk) => this.receive(chunk)); socket.on("error", () => this.fail(new Error("CDP socket error"))); socket.on("close", () => this.fail(new Error("CDP socket closed"))); if (head.length) this.receive(head); resolve();
      });
      request.once("error", (error) => { clearTimeout(timer); reject(new Error(`CDP connection failed: ${error.message}`)); }); request.end();
    });
  }
  receive(chunk) {
    this.buffer = Buffer.concat([this.buffer, chunk]);
    while (this.buffer.length >= 2) {
      const first = this.buffer[0], second = this.buffer[1]; let offset = 2, length = second & 127;
      if (length === 126) { if (this.buffer.length < 4) return; length = this.buffer.readUInt16BE(2); offset = 4; }
      else if (length === 127) { if (this.buffer.length < 10) return; const size = this.buffer.readBigUInt64BE(2); if (size > BigInt(16 * 1024 * 1024)) { this.close(); return; } length = Number(size); offset = 10; }
      if (this.buffer.length < offset + length) return;
      const opcode = first & 15, payload = this.buffer.subarray(offset, offset + length); this.buffer = this.buffer.subarray(offset + length);
      if (opcode === 8) { this.close(); return; } if (opcode !== 1) continue;
      try { const message = JSON.parse(payload.toString("utf8")); const waiter = this.pending.get(message.id); if (!waiter) continue; clearTimeout(waiter.timer); this.pending.delete(message.id); message.error ? waiter.reject(new Error(message.error.message)) : waiter.resolve(message.result); } catch { this.close(); }
    }
  }
  writeText(text) { const payload = Buffer.from(text); const mask = crypto.randomBytes(4); const extra = payload.length < 126 ? 0 : payload.length <= 65535 ? 2 : 8; const frame = Buffer.alloc(2 + extra + 4 + payload.length); frame[0] = 0x81; if (extra === 0) frame[1] = 0x80 | payload.length; else if (extra === 2) { frame[1] = 0xfe; frame.writeUInt16BE(payload.length, 2); } else { frame[1] = 0xff; frame.writeBigUInt64BE(BigInt(payload.length), 2); } const start = 2 + extra; mask.copy(frame, start); for (let i = 0; i < payload.length; i++) frame[start + 4 + i] = payload[i] ^ mask[i % 4]; this.socket.write(frame); }
  send(method, params = {}) { return new Promise((resolve, reject) => { const id = ++this.id; const timer = setTimeout(() => { this.pending.delete(id); reject(new Error(`CDP command timed out: ${method}`)); }, 10000); this.pending.set(id, { resolve, reject, timer }); try { this.writeText(JSON.stringify({ id, method, params })); } catch (error) { clearTimeout(timer); this.pending.delete(id); reject(error); } }); }
  async eval(expression) { const result = await this.send("Runtime.evaluate", { expression, awaitPromise: true, returnByValue: true }); if (result.exceptionDetails) throw new Error(result.exceptionDetails.text || "Renderer evaluation failed"); return result.result?.value; }
  fail(error) { for (const waiter of this.pending.values()) { clearTimeout(waiter.timer); waiter.reject(error); } this.pending.clear(); }
  close() { try { this.socket?.destroy(); } catch {} this.fail(new Error("CDP session closed")); }
}

const RENDERER_CHILD_MARKUP = '<div class="ym-portrait"></div>';
const FORBIDDEN_RENDERER_MARKERS = [
  "ym-actions",
  "ym-status",
  "ym-banner",
  "ym-card",
  "ym-caption",
  "ym-copy",
  "ym-frame",
  "ym-hero",
  "ym-label",
  "ym-note",
  "ym-photo",
  "ym-tags",
  "ym-wallpaper",
  "ym-veil",
  "padding-top:",
];

function rendererPayload(payload) {
  return {
    theme: {
      id: payload.theme.id,
      accent: payload.theme.accent,
      surface: payload.theme.surface,
      ink: payload.theme.ink,
    },
    hero: payload.hero,
  };
}

function buildRendererCss(data, id) {
  return `html[data-yang-mi-skin] .app-header-tint{background:#f7fbf6!important;border-bottom-color:#c5d4c2!important}html[data-yang-mi-skin] .app-shell-left-panel{background:#f3f8f1!important;border-right-color:#c5d4c2!important}html[data-yang-mi-skin] main,html[data-yang-mi-skin] [role="main"]{background-color:transparent!important}html[data-yang-mi-skin] .app-shell-main-content-frame{background-color:transparent!important}html[data-yang-mi-skin] textarea,html[data-yang-mi-skin] [contenteditable="true"],html[data-yang-mi-skin] [contenteditable="plaintext-only"]{border-color:#b9cfb5!important;caret-color:${data.theme.ink}}html[data-yang-mi-skin] body>#${id}{--ym-workspace-left:clamp(240px,14.25vw,310px);pointer-events:none;position:fixed;inset:0;z-index:0;overflow:hidden}html[data-yang-mi-skin] body>:not(#${id}){position:relative;z-index:1}#${id} .ym-portrait{pointer-events:none;position:absolute;z-index:0;left:var(--ym-workspace-left);right:0;top:0;bottom:0;background-color:${data.theme.surface};background-image:url("${data.hero}");background-size:contain;background-repeat:no-repeat;background-position:center;opacity:.38;filter:saturate(.7) contrast(1) brightness(1.12)}`;
}

function fingerprintText(value) {
  let hash = 0x811c9dc5;
  for (let index = 0; index < value.length; index++) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 0x01000193);
  }
  return (hash >>> 0).toString(16).padStart(8, "0");
}

function rendererFingerprint(payload) {
  return fingerprintText(buildRendererCss(rendererPayload(payload), "yang-mi-codex-skin"));
}

export function buildRenderer(payload) {
  const data = rendererPayload(payload);
  const fingerprint = rendererFingerprint(payload);
  return `(() => { const data=${JSON.stringify(data)},id='yang-mi-codex-skin',buildRendererCss=${buildRendererCss.toString()}; document.getElementById(id)?.remove(); document.getElementById(id+'-style')?.remove(); const layer=document.createElement('div'); layer.id=id; layer.setAttribute('aria-hidden','true'); layer.style.pointerEvents='none'; layer.innerHTML='${RENDERER_CHILD_MARKUP}'; const style=document.createElement('style'); style.id=id+'-style'; style.setAttribute('data-yang-mi-version','${VERSION}'); style.setAttribute('data-yang-mi-fingerprint','${fingerprint}'); style.textContent=buildRendererCss(data,id); document.head.append(style); document.body.append(layer); document.documentElement.dataset.yangMiSkin=data.theme.id; window.__YANG_MI_CODEX_SKIN__={version:'${VERSION}',theme:data.theme.id}; return window.__YANG_MI_CODEX_SKIN__; })()`;
}

function countOccurrences(source, value) {
  if (!value) return 0;
  let count = 0;
  for (let offset = 0; (offset = source.indexOf(value, offset)) !== -1; offset += value.length) count++;
  return count;
}

export function validateRendererPayload(payload, script) {
  for (const marker of FORBIDDEN_RENDERER_MARKERS) {
    if (script.includes(marker)) throw new Error(`Renderer contains forbidden marker: ${marker}`);
  }
  const childMarkup = /layer\.innerHTML='([^']*)'/.exec(script)?.[1];
  if (childMarkup !== RENDERER_CHILD_MARKUP) throw new Error("Renderer child structure is not restrained");
  if (!script.includes("layer.setAttribute('aria-hidden','true')") || !script.includes("pointer-events:none")) {
    throw new Error("Renderer accessibility boundary is incomplete");
  }
  if (script !== buildRenderer(payload)) throw new Error("Renderer script does not exactly match the approved renderer");

  const hero = decodeDataImage(payload.hero);
  const polaroid = decodeDataImage(payload.polaroid);
  if (countOccurrences(script, payload.hero) !== 1) throw new Error("Renderer must embed the hero exactly once");
  const heroReferences = countOccurrences(script, "data.hero");
  const polaroidReferences = countOccurrences(script, "data.polaroid") + countOccurrences(script, '"polaroid":');
  if (heroReferences !== 1) throw new Error("Renderer must reference the hero exactly once");
  if (polaroidReferences !== 0) throw new Error("Renderer must not reference the polaroid");

  return {
    pass: true,
    theme: payload.theme.id,
    backgroundSource: payload.backgroundSource,
    heroBytes: hero.bytes.length,
    polaroidBytes: polaroid.bytes.length,
    rendererBytes: Buffer.byteLength(script),
    rendererCss: buildRendererCss(rendererPayload(payload), "yang-mi-codex-skin"),
    visualNodes: ["ym-portrait"],
    heroReferences,
    polaroidReferences,
    portraitHiddenAt: null,
  };
}
const probe = `(() => {
  const anyVisible=${anyVisible.toString()};
  const isEditableComposerCandidate=${isEditableComposerCandidate.toString()};
  const isCodexShellReady=${isCodexShellReady.toString()};
  const fingerprintText=${fingerprintText.toString()};
  const visible=(element) => {
    const style=getComputedStyle(element), rect=element.getBoundingClientRect();
    return !element.hidden && style.display!=='none' && style.visibility!=='hidden' && style.opacity!=='0' && rect.width>0 && rect.height>0;
  };
  const shells=[...document.querySelectorAll('main,[role="main"],.app-shell-main-content-frame,.main-surface')].map((element) => visible(element));
  const composers=[...document.querySelectorAll('textarea,[contenteditable]')].map((element) => ({
    kind:element.tagName==='TEXTAREA'?'textarea':'contenteditable',
    visible:visible(element),
    readOnly:element.readOnly===true,
    disabled:element.disabled===true,
    contentEditable:element.getAttribute('contenteditable') ?? element.contentEditable,
    ariaDisabled:element.getAttribute('aria-disabled'),
  }));
  const layers=[...document.querySelectorAll('#yang-mi-codex-skin')];
  const styles=[...document.querySelectorAll('#yang-mi-codex-skin-style')];
  const layer=layers[0] ?? null;
  const style=styles[0] ?? null;
  const styleText=style?.textContent ?? '';
  const renderer={
    layerCount:layers.length,
    styleCount:styles.length,
    childClasses:layer ? [...layer.children].map((child) => child.getAttribute('class')) : [],
    ariaHidden:layer?.getAttribute('aria-hidden') ?? null,
    layerPointerEvents:layer?.style.pointerEvents ?? null,
    computedPointerEvents:layer ? getComputedStyle(layer).pointerEvents : null,
    styleVersion:style?.getAttribute('data-yang-mi-version') ?? null,
    styleDeclaredFingerprint:style?.getAttribute('data-yang-mi-fingerprint') ?? null,
    styleComputedFingerprint:style ? fingerprintText(styleText) : null,
    styleTextLength:styleText.length,
  };
  return { app:location.protocol==='app:', ready:isCodexShellReady({ readyState:document.readyState, body:!!document.body, shells, composers }), skin:window.__YANG_MI_CODEX_SKIN__ ?? null, renderer };
})()`;

function runSelfTest() {
  const fixtures = [
    [{ readyState: "complete", body: true, shells: [false], composers: [] }, false],
    [{ readyState: "complete", body: true, shells: [false, true], composers: [] }, true],
    [{ readyState: "interactive", body: true, shells: [], composers: [{ kind: "textarea", visible: true }] }, true],
    [{ readyState: "complete", body: true, shells: [], composers: [{ kind: "contenteditable", visible: true, contentEditable: "true" }] }, true],
    [{ readyState: "complete", body: true, shells: [], composers: [{ kind: "contenteditable", visible: true, contentEditable: "plaintext-only" }] }, true],
    [{ readyState: "complete", body: true, shells: [], composers: [{ kind: "textarea", visible: true, readOnly: true }] }, false],
    [{ readyState: "complete", body: true, shells: [], composers: [{ kind: "textarea", visible: true, disabled: true }] }, false],
    [{ readyState: "complete", body: true, shells: [], composers: [{ kind: "contenteditable", visible: true, contentEditable: "true", ariaDisabled: "true" }] }, false],
    [{ readyState: "complete", body: true, shells: [], composers: [{ kind: "textarea", visible: false }] }, false],
  ];
  for (const [snapshot, expected] of fixtures) {
    if (isCodexShellReady(snapshot) !== expected) throw new Error("Readiness self-test failed");
  }
  console.log(JSON.stringify({ pass: true, fixtures: fixtures.length }));
}

async function run(options) {
  if (options.mode === "self-test") { runSelfTest(); return; }
  if (options.mode === "check") { const payload = await buildPayload(options.theme); console.log(JSON.stringify(validateRendererPayload(payload, buildRenderer(payload)))); return; }
  const payload = options.mode === "remove" ? null : await buildPayload(options.theme);
  const expectedFingerprint = payload ? rendererFingerprint(payload) : null;
  const attempt = async () => {
    const targets = await getTargets(options.port, options.browserId);
    let matched = 0;
    let cleaned = 0;
    let verifiedRenderer = null;
    for (const target of targets.pages) {
      const cdp = new Cdp(target, options.port);
      try {
        await cdp.open();
        if (options.mode !== "remove" && !isCodexWorkspaceTarget(target)) {
          await cdp.eval("(() => { const id='yang-mi-codex-skin'; document.querySelectorAll('#'+id).forEach((element) => element.remove()); document.querySelectorAll('#'+id+'-style').forEach((element) => element.remove()); delete document.documentElement.dataset.yangMiSkin; delete window.__YANG_MI_CODEX_SKIN__; })()");
          continue;
        }
        if (options.mode === "remove") {
          const removed = await cdp.eval("(() => { const id='yang-mi-codex-skin'; document.querySelectorAll('#'+id).forEach((element) => element.remove()); document.querySelectorAll('#'+id+'-style').forEach((element) => element.remove()); delete document.documentElement.dataset.yangMiSkin; delete window.__YANG_MI_CODEX_SKIN__; return document.querySelectorAll('#'+id).length===0 && document.querySelectorAll('#'+id+'-style').length===0 && !document.documentElement.dataset.yangMiSkin && !window.__YANG_MI_CODEX_SKIN__; })()");
          if (removed) cleaned++;
          continue;
        }
        const before = await cdp.eval(probe);
        if (!shouldProcessTarget(options.mode, before)) continue;
        if (options.mode !== "verify") await cdp.eval(buildRenderer(payload));
        const after = await cdp.eval(probe);
        if (isExactRendererState(after, payload.theme.id, expectedFingerprint)) {
          matched++;
          verifiedRenderer = after.renderer;
        }
      } finally {
        cdp.close();
      }
    }
    if (options.mode === "remove") {
      if (!allTargetsCleaned(targets.pages.length, cleaned)) throw new Error(`Failed to clean every Codex app target: ${cleaned}/${targets.pages.length}`);
      console.log(JSON.stringify({ pass: true, theme: null, targets: cleaned }));
      return;
    }
    if (!matched) throw new Error("No target matched the exact Codex shell and renderer state");
    console.log(JSON.stringify({ pass: true, theme: payload.theme.id, targets: matched, renderer: verifiedRenderer }));
  };
  if (options.mode !== "watch") return attempt();
  await attempt().catch(() => {});
  setInterval(() => attempt().catch(() => {}), 3000);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) run(args(process.argv.slice(2))).catch((error) => { console.error(error.message); process.exitCode = 1; });
