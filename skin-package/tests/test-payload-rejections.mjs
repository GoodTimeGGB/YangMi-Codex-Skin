import assert from "node:assert/strict";
import * as injector from "../shared/injector.mjs";

const jpegFrame = Buffer.from([0x08, 0x00, 0x01, 0x00, 0x01, 0x01, 0x01, 0x11, 0x00]);
const jpegDqt = Buffer.concat([Buffer.from([0x00]), Buffer.alloc(64, 0x01)]);
const jpegDht = Buffer.from([0x00, 0x01, ...Buffer.alloc(15), 0x00, 0x10, 0x01, ...Buffer.alloc(15), 0x00]);
const jpegDac = Buffer.from([0x00, 0x00]);

function jpegSegment(marker, body) {
  const segment = Buffer.alloc(body.length + 4);
  segment[0] = 0xff;
  segment[1] = marker;
  segment.writeUInt16BE(body.length + 2, 2);
  body.copy(segment, 4);
  return segment;
}

function buildJpeg({ sof, dqt = jpegDqt, codingSegments, scans }) {
  const chunks = [
    Buffer.from([0xff, 0xd8]),
    jpegSegment(0xdb, dqt),
    jpegSegment(sof, jpegFrame),
    ...codingSegments.map(([marker, body]) => jpegSegment(marker, body)),
    jpegSegment(0xfe, Buffer.alloc(960, 0x20)),
  ];
  for (const [index, scan] of scans.entries()) {
    chunks.push(jpegSegment(0xda, scan.header));
    chunks.push(Buffer.from([0x7f]));
    if (index === scans.length - 1) continue;
    chunks.push(...scan.after.map(([marker, body]) => jpegSegment(marker, body)));
  }
  return Buffer.concat([...chunks, Buffer.from([0xff, 0xd9])]);
}

assert.equal(typeof injector.decodeDataImage, "function");
assert.throws(
  () => injector.decodeDataImage("data:image/jpeg;base64,not base64"),
  /Malformed image data URL/,
);
assert.throws(
  () => injector.decodeDataImage("data:image/jpeg;base64,QUFBQQ=="),
  /Invalid JPEG structure/,
);
assert.throws(
  () => injector.decodeDataImage("data:image/webp;base64,UklGRgAAAAAATk9QRQ=="),
  /Invalid WebP structure/,
);

const forgedJpeg = Buffer.alloc(1024);
forgedJpeg.set([0xff, 0xd8, 0xff], 0);
forgedJpeg.set([0xff, 0xd9], forgedJpeg.length - 2);
assert.throws(
  () => injector.decodeDataImage(`data:image/jpeg;base64,${forgedJpeg.toString("base64")}`),
  /Invalid JPEG structure/,
);

const invalidScanJpeg = Buffer.alloc(1024);
invalidScanJpeg.set([0xff, 0xd8, 0xff, 0xc0, 0x00, 0x0b, 0x08, 0x00, 0x01, 0x00, 0x01, 0x01, 0x01, 0x11, 0x00], 0);
invalidScanJpeg.set([0xff, 0xda, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3f, 0x00, 0xff, 0x02], 15);
invalidScanJpeg.set([0xff, 0xd9], invalidScanJpeg.length - 2);
assert.throws(
  () => injector.decodeDataImage(`data:image/jpeg;base64,${invalidScanJpeg.toString("base64")}`),
  /Invalid JPEG structure/,
);

const tablelessJpeg = Buffer.concat([
  Buffer.from([0xff, 0xd8]),
  jpegSegment(0xfe, Buffer.alloc(1000, 0x20)),
  jpegSegment(0xc0, jpegFrame),
  jpegSegment(0xda, Buffer.from([0x01, 0x01, 0x00, 0x00, 0x3f, 0x00])),
  Buffer.from([0x7f, 0xff, 0xd9]),
]);
assert.throws(
  () => injector.decodeDataImage(`data:image/jpeg;base64,${tablelessJpeg.toString("base64")}`),
  /Invalid JPEG structure/,
);

const huffmanSofWithDac = buildJpeg({
  sof: 0xc0,
  codingSegments: [[0xcc, jpegDac]],
  scans: [{ header: Buffer.from([0x01, 0x01, 0x00, 0x00, 0x3f, 0x00]), after: [] }],
});
assert.throws(
  () => injector.decodeDataImage(`data:image/jpeg;base64,${huffmanSofWithDac.toString("base64")}`),
  /Invalid JPEG structure/,
);

const huffmanSofWithEmptyDht = buildJpeg({
  sof: 0xc0,
  codingSegments: [[0xc4, Buffer.alloc(0)]],
  scans: [{ header: Buffer.from([0x01, 0x01, 0x00, 0x00, 0x3f, 0x00]), after: [] }],
});
assert.throws(
  () => injector.decodeDataImage(`data:image/jpeg;base64,${huffmanSofWithEmptyDht.toString("base64")}`),
  /Invalid JPEG structure/,
);

const huffmanSofWithEmptyDqt = buildJpeg({
  sof: 0xc0,
  dqt: Buffer.alloc(0),
  codingSegments: [[0xc4, jpegDht]],
  scans: [{ header: Buffer.from([0x01, 0x01, 0x00, 0x00, 0x3f, 0x00]), after: [] }],
});
assert.throws(
  () => injector.decodeDataImage(`data:image/jpeg;base64,${huffmanSofWithEmptyDqt.toString("base64")}`),
  /Invalid JPEG structure/,
);

const arithmeticSofWithDht = buildJpeg({
  sof: 0xc9,
  codingSegments: [[0xc4, jpegDht]],
  scans: [{ header: Buffer.from([0x01, 0x01, 0x00, 0x00, 0x3f, 0x00]), after: [] }],
});
assert.throws(
  () => injector.decodeDataImage(`data:image/jpeg;base64,${arithmeticSofWithDht.toString("base64")}`),
  /Invalid JPEG structure/,
);

const progressiveJpeg = buildJpeg({
  sof: 0xc2,
  codingSegments: [[0xc4, jpegDht]],
  scans: [
    { header: Buffer.from([0x01, 0x01, 0x00, 0x00, 0x00, 0x00]), after: [[0xc4, jpegDht]] },
    { header: Buffer.from([0x01, 0x01, 0x00, 0x01, 0x3f, 0x00]), after: [] },
  ],
});
assert.doesNotThrow(
  () => injector.decodeDataImage(`data:image/jpeg;base64,${progressiveJpeg.toString("base64")}`),
);

const forgedWebp = Buffer.alloc(1024);
forgedWebp.write("RIFF", 0, "ascii");
forgedWebp.writeUInt32LE(forgedWebp.length - 8, 4);
forgedWebp.write("WEBP", 8, "ascii");
forgedWebp.write("JUNK", 12, "ascii");
forgedWebp.writeUInt32LE(forgedWebp.length - 20, 16);
assert.throws(
  () => injector.decodeDataImage(`data:image/webp;base64,${forgedWebp.toString("base64")}`),
  /Invalid WebP structure/,
);

const vp8xOnlyWebp = Buffer.alloc(1024, 0x20);
vp8xOnlyWebp.write("RIFF", 0, "ascii");
vp8xOnlyWebp.writeUInt32LE(vp8xOnlyWebp.length - 8, 4);
vp8xOnlyWebp.write("WEBP", 8, "ascii");
vp8xOnlyWebp.write("VP8X", 12, "ascii");
vp8xOnlyWebp.writeUInt32LE(10, 16);
vp8xOnlyWebp.fill(0, 20, 30);
vp8xOnlyWebp[20] = 0x04;
vp8xOnlyWebp.write("XMP ", 30, "ascii");
vp8xOnlyWebp.writeUInt32LE(vp8xOnlyWebp.length - 38, 34);
vp8xOnlyWebp.write('<x:xmpmeta xmlns:x="adobe:ns:meta/"></x:xmpmeta>', 38, "ascii");
assert.throws(
  () => injector.decodeDataImage(`data:image/webp;base64,${vp8xOnlyWebp.toString("base64")}`),
  /Invalid WebP structure/,
);

const vp8lWithReservedVersion = Buffer.alloc(1024);
vp8lWithReservedVersion.write("RIFF", 0, "ascii");
vp8lWithReservedVersion.writeUInt32LE(vp8lWithReservedVersion.length - 8, 4);
vp8lWithReservedVersion.write("WEBP", 8, "ascii");
vp8lWithReservedVersion.write("VP8L", 12, "ascii");
vp8lWithReservedVersion.writeUInt32LE(vp8lWithReservedVersion.length - 20, 16);
vp8lWithReservedVersion[20] = 0x2f;
vp8lWithReservedVersion.writeUInt32LE(0x20000000, 21);
assert.throws(
  () => injector.decodeDataImage(`data:image/webp;base64,${vp8lWithReservedVersion.toString("base64")}`),
  /Invalid WebP structure/,
);

for (const themeId of ["floral-retro", "woodland-white", "bridal-moonlight", "noir-silver"]) {
  const payload = await injector.buildPayload(themeId);
  assert.doesNotThrow(() => injector.decodeDataImage(payload.hero), `${themeId} hero must validate`);
  assert.doesNotThrow(() => injector.decodeDataImage(payload.polaroid), `${themeId} polaroid must validate`);
}

assert.equal(typeof injector.validateRendererPayload, "function");
assert.throws(
  () => injector.validateRendererPayload({}, "<div class=\"ym-actions\"></div>"),
  /Renderer contains forbidden marker: ym-actions/,
);

console.log("PASS: payload validation rejects forbidden markers and malformed images.");
