import sodium from "libsodium-wrappers-sumo";
import { hkdfSync, createCipheriv, createHash } from "node:crypto";
import { writeFileSync } from "node:fs";
await sodium.ready;
const passphrase = "Relay café 🔐 sample passphrase",
  salt = Buffer.alloc(16, 7),
  dek = Buffer.alloc(32, 9),
  nonce = Buffer.alloc(12, 3);
const master = Buffer.from(
  sodium.crypto_pwhash(
    32,
    passphrase.normalize("NFKC"),
    salt,
    3,
    67108864,
    sodium.crypto_pwhash_ALG_ARGON2ID13,
  ),
);
const hkdf = (key, label) =>
  Buffer.from(hkdfSync("sha256", key, Buffer.alloc(0), label, 32));
const kek = hkdf(master, "relay/v1/kek"),
  auth = hkdf(master, "relay/v1/auth");
const account = "11111111-1111-4111-8111-111111111111",
  row = "22222222-2222-4222-8222-222222222222",
  plaintext = Buffer.from('{"canary":"RELAYCANARY"}');
const padded = Buffer.concat([
  plaintext,
  Buffer.from([128]),
  Buffer.alloc(512 - plaintext.length - 1),
]);
const cipher = createCipheriv("aes-256-gcm", hkdf(dek, "relay/v1/blob"), nonce);
cipher.setAAD(Buffer.from(`relay/v1/blob|${account}|${row}|1|1`));
const envelope = Buffer.concat([
  Buffer.from([1, 0, 0, 0, 1]),
  nonce,
  cipher.update(padded),
  cipher.final(),
  cipher.getAuthTag(),
]);
const vector = {
  passphrase,
  salt: salt.toString("hex"),
  dek: dek.toString("hex"),
  nonce: nonce.toString("hex"),
  account,
  row,
  kek: kek.toString("hex"),
  auth: auth.toString("hex"),
  verifier: createHash("sha256").update(auth).digest("hex"),
  plaintext: plaintext.toString(),
  envelope: envelope.toString("base64url"),
};
writeFileSync(
  new URL("../packages/crypto-vectors.json", import.meta.url),
  JSON.stringify(vector, null, 2) + "\n",
);
console.log("Cross-platform crypto vector generated.");
