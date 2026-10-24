import sodium from "libsodium-wrappers-sumo";
export const from64 = (s) =>
  Uint8Array.from(
    atob(
      s
        .replace(/-/g, "+")
        .replace(/_/g, "/")
        .padEnd(Math.ceil(s.length / 4) * 4, "="),
    ),
    (c) => c.charCodeAt(0),
  );
export const to64 = (b) =>
  btoa(String.fromCharCode(...new Uint8Array(b)))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
const enc = (s) => new TextEncoder().encode(s);
export async function hkdf(key, label) {
  const k = await crypto.subtle.importKey("raw", key, "HKDF", false, [
    "deriveBits",
  ]);
  return new Uint8Array(
    await crypto.subtle.deriveBits(
      {
        name: "HKDF",
        hash: "SHA-256",
        salt: new Uint8Array(),
        info: enc(label),
      },
      k,
      256,
    ),
  );
}
export async function derive(passphrase, salt) {
  await sodium.ready;
  const master = sodium.crypto_pwhash(
    32,
    passphrase.normalize("NFKC"),
    salt,
    3,
    67108864,
    sodium.crypto_pwhash_ALG_ARGON2ID13,
  );
  const kek = await hkdf(master, "relay/v1/kek"),
    auth = await hkdf(master, "relay/v1/auth");
  master.fill(0);
  return { kek, auth };
}
export async function unwrap(wrapped, kek, account) {
  const key = await crypto.subtle.importKey("raw", kek, "AES-GCM", false, [
    "decrypt",
  ]);
  return new Uint8Array(
    await crypto.subtle.decrypt(
      {
        name: "AES-GCM",
        iv: wrapped.slice(0, 12),
        additionalData: enc(`relay/v1/wrap|${account}|1|passphrase`),
      },
      key,
      wrapped.slice(12),
    ),
  );
}
export async function openBlob(item, dek, account) {
  const data = from64(item.envelope);
  if (
    data[0] !== 1 ||
    new DataView(data.buffer).getUint32(1) !== item.key_version
  )
    throw Error("Unsupported encrypted record.");
  const key = await crypto.subtle.importKey(
    "raw",
    await hkdf(dek, "relay/v1/blob"),
    "AES-GCM",
    false,
    ["decrypt"],
  );
  const padded = new Uint8Array(
    await crypto.subtle.decrypt(
      {
        name: "AES-GCM",
        iv: data.slice(5, 17),
        additionalData: enc(
          `relay/v1/blob|${account}|${item.row_id}|${item.version}|${item.key_version}`,
        ),
      },
      key,
      data.slice(17),
    ),
  );
  let i = padded.length - 1;
  while (i >= 0 && padded[i] === 0) i--;
  if (padded[i] !== 128) throw Error("Invalid encrypted padding.");
  const obj = JSON.parse(new TextDecoder().decode(padded.slice(0, i)));
  if (
    obj.id.toLowerCase() !== item.row_id ||
    obj.schema !== "relay.agreement/1"
  )
    throw Error("Unsupported record.");
  return obj;
}
export async function sealBlob(obj, dek, account, version) {
  const clear = enc(JSON.stringify(obj)),
    bucket = [512, 1024, 2048, 4096, 8192, 16384, 32768, 65536].find(
      (n) => n > clear.length,
    );
  if (!bucket) throw Error("Agreement is too large.");
  const padded = new Uint8Array(bucket);
  padded.set(clear);
  padded[clear.length] = 128;
  const key = await crypto.subtle.importKey(
      "raw",
      await hkdf(dek, "relay/v1/blob"),
      "AES-GCM",
      false,
      ["encrypt"],
    ),
    nonce = crypto.getRandomValues(new Uint8Array(12));
  const ciphertext = new Uint8Array(
    await crypto.subtle.encrypt(
      {
        name: "AES-GCM",
        iv: nonce,
        additionalData: enc(
          `relay/v1/blob|${account}|${obj.id.toLowerCase()}|${version}|1`,
        ),
      },
      key,
      padded,
    ),
  );
  const result = new Uint8Array(17 + ciphertext.length);
  result.set([1, 0, 0, 0, 1]);
  result.set(nonce, 5);
  result.set(ciphertext, 17);
  return to64(result);
}
