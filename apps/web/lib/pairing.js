import { from64, to64 } from "./crypto.js";
const enc = new TextEncoder();
export const pairingHash = async key => to64(await crypto.subtle.digest("SHA-256", key));
export const pairingCode = async key => (await pairingHash(key)).slice(0, 6).toUpperCase();
export function pairingURL(origin, id, key) {
  const url = new URL("/workspace", origin);
  url.hash = "pair=" + to64(enc.encode(JSON.stringify({ v: 1, id, key: to64(key) })));
  return url.href;
}
export function parsePairing(text, expectedOrigin) {
  const url = new URL(text.trim());
  if (url.username || url.password || url.pathname !== "/workspace" || url.search ||
      !(url.protocol === "https:" || (url.protocol === "http:" && ["localhost", "127.0.0.1", "[::1]"].includes(url.hostname))))
    throw Error("Use a Relay pairing link with a secure server address.");
  if (expectedOrigin && url.origin !== expectedOrigin)
    throw Error("Open Relay at " + url.origin + " to use this pairing code.");
  const payload = JSON.parse(new TextDecoder().decode(from64(new URLSearchParams(url.hash.slice(1)).get("pair") || "")));
  if (payload.v !== 1 || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(payload.id) ||
      !/^[A-Za-z0-9_-]{43}$/.test(payload.key) || from64(payload.key).length !== 32)
    throw Error("This pairing code is invalid. Show a new code on your other device.");
  return { id: payload.id.toLowerCase(), key: from64(payload.key), origin: url.origin };
}
export async function pairingWrap(dek, secret, account, id, decrypt = false) {
  const key = await crypto.subtle.importKey("raw", secret, "AES-GCM", false, [decrypt ? "decrypt" : "encrypt"]);
  const iv = decrypt ? dek.slice(0, 12) : crypto.getRandomValues(new Uint8Array(12));
  const params = { name: "AES-GCM", iv, additionalData: enc.encode(`relay/v1/wrap|${account.toLowerCase()}|1|pairing:${id.toLowerCase()}`) };
  const result = new Uint8Array(await crypto.subtle[decrypt ? "decrypt" : "encrypt"](params, key, decrypt ? dek.slice(12) : dek));
  if (decrypt) { if (result.length !== 32) throw Error("Invalid workspace key."); return result; }
  const envelope = new Uint8Array(12 + result.length);
  envelope.set(iv); envelope.set(result, 12);
  return envelope;
}
export async function pairingAPI(path, body, method = body ? "POST" : "GET", token) {
  const response = await fetch("/api/v1/" + path, { method, cache: "no-store", headers: {
    "Content-Type": "application/json", ...(token ? { Authorization: "Bearer " + token } : {}),
  }, ...(body ? { body: JSON.stringify(body) } : {}) });
  const data = response.status === 204 ? {} : await response.json();
  if (!response.ok) { const error = Error(data.error?.message || "Pairing failed. Try a new code."); error.status = response.status; throw error; }
  return data;
}
