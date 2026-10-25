import test from "node:test";
import assert from "node:assert/strict";
import { pairingURL, parsePairing, pairingWrap, pairingCode } from "./pairing.js";
import { to64, from64 } from "./crypto.js";
import QRCode from "qrcode";
import jsQR from "jsqr";
// Fixed envelope shared with Swift: AES-GCM nonce | ciphertext | tag.
const fixture = {
  id: "11111111-2222-4333-8444-555555555555", account: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
  key: new Uint8Array(32).fill(7), dek: new Uint8Array(32).fill(9),
};
test("displayed pairing QR can be decoded by the browser scanner", () => {
  const link = pairingURL("https://relay.example", fixture.id, fixture.key);
  const { modules } = QRCode.create(link, { errorCorrectionLevel: "M" });
  const scale = 6, margin = 4, size = (modules.size + margin * 2) * scale;
  const pixels = new Uint8ClampedArray(size * size * 4).fill(255);
  for (let y = 0; y < modules.size; y++) for (let x = 0; x < modules.size; x++) {
    if (!modules.get(y, x)) continue;
    for (let dy = 0; dy < scale; dy++) for (let dx = 0; dx < scale; dx++) {
      const offset = (((y + margin) * scale + dy) * size + (x + margin) * scale + dx) * 4;
      pixels[offset] = 0; pixels[offset + 1] = 0; pixels[offset + 2] = 0;
    }
  }
  assert.equal(jsQR(pixels, size, size)?.data, link);
});
test("pairing links retain the server origin and keep the secret out of URL query/path", async () => {
  const { id, key } = fixture;
  const link = pairingURL("https://relay.example", id, key), url = new URL(link);
  assert.equal(url.search, ""); assert.equal(url.pathname, "/workspace");
  const parsed = parsePairing(link, "https://relay.example");
  assert.equal(parsed.id, id); assert.deepEqual(parsed.key, key);
  assert.throws(() => parsePairing(link, "https://different.example"));
  for (const origin of ["http://relay.example", "https://name:secret@relay.example"]) {
    assert.throws(() => parsePairing(pairingURL(origin, id, key)));
  }
  assert.throws(() => parsePairing("https://relay.example/workspace#pair=invalid"));
  assert.equal((await pairingCode(key)).length, 6);
});
test("pairing envelope authenticates account, invitation, and secret", async () => {
  const { id, account, key, dek } = fixture;
  const encrypted = await pairingWrap(dek, key, account, id);
  assert.equal(encrypted.length, 60);
  assert.deepEqual(await pairingWrap(encrypted, key, account, id, true), dek);
  await assert.rejects(pairingWrap(encrypted, new Uint8Array(32).fill(8), account, id, true));
  await assert.rejects(pairingWrap(encrypted, key, "bbbbbbbb-bbbb-4ccc-8ddd-eeeeeeeeeeee", id, true));
  await assert.rejects(pairingWrap(encrypted, key, account, "22222222-2222-4333-8444-555555555555", true));
  encrypted[20] ^= 1;
  await assert.rejects(pairingWrap(encrypted, key, account, id, true));
});
test("Swift and browser pairing share the same encryption format", async () => {
  const envelope = from64("AAECAwQFBgcICQoLEYjgeRQA0EB-u-yV61Fl8-g1v4cRa344H8dqs4feZAy5QfX5iB7szHg41pGbnUhj");
  assert.deepEqual(await pairingWrap(envelope, fixture.key, fixture.account, fixture.id, true), fixture.dek);
  assert.equal(to64(envelope), "AAECAwQFBgcICQoLEYjgeRQA0EB-u-yV61Fl8-g1v4cRa344H8dqs4feZAy5QfX5iB7szHg41pGbnUhj");
});
