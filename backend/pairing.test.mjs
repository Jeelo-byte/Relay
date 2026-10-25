import test from "node:test";
import assert from "node:assert/strict";
import { randomBytes, randomUUID, createHash } from "node:crypto";
import { neon } from "@neondatabase/serverless";
import { handleAPI } from "./api.mjs";
const b64 = n => randomBytes(n).toString("base64url");
const hash = s => createHash("sha256").update(Buffer.from(s, "base64url")).digest("base64url");
const ip = randomUUID();
async function call(path, body, token, method = body ? "POST" : "GET") {
  const response = await handleAPI(new Request("https://relay.test/api/v1/" + path, { method,
    headers: { "content-type": "application/json", "x-forwarded-for": ip, ...(token ? { authorization: "Bearer " + token } : {}) },
    ...(body ? { body: JSON.stringify(body) } : {}),
  }));
  return { status: response.status, data: response.status === 204 ? {} : await response.json() };
}
async function account() {
  const handle = "pair_" + randomBytes(6).toString("hex"), auth = b64(32), id = randomUUID();
  const result = await call("accounts", { account_id: id, handle, kdf_salt: b64(16),
    kdf_params: { alg: "argon2id13", ops: 3, mem: 67108864 }, auth_verifier: hash(auth), recovery_verifier: b64(32),
    wraps: ["passphrase", "recovery"].map(wrap_type => ({ key_version: 1, wrap_type, wrapped_dek: b64(60) })),
    device: { device_id: randomUUID(), priority: 4 } });
  assert.equal(result.status, 201, JSON.stringify(result.data));
  return { handle, auth, id, token: result.data.token };
}
async function invite(owner) {
  const id = randomUUID(), secret = b64(32), encrypted = b64(60);
  const result = await call("pairings", { pairing_id: id, key_hash: hash(secret), encrypted_dek: encrypted }, owner.token);
  assert.equal(result.status, 201, JSON.stringify(result.data));
  return { id, secret, encrypted, path: "pairings/" + id, device: { device_id: randomUUID(), priority: 2 }, poll: b64(32) };
}
const join = (p, overrides = {}) => call(p.path + "/join", { key_hash: hash(p.secret), poll_hash: hash(p.poll), device: p.device, ...overrides });
const claim = p => call(p.path + "/claim", { poll_key: p.poll });

test("pairing requires approval, binds both secrets, consumes once, and invalidates stale invitations", { skip: !process.env.DATABASE_URL }, async () => {
  const sql = neon(process.env.DATABASE_URL), owner = await account(), stranger = await account();
  try {
    assert.equal((await call("pairings", { pairing_id: randomUUID(), key_hash: b64(32), encrypted_dek: b64(60) })).status, 401);
    const p = await invite(owner);
    assert.equal((await join(p, { key_hash: b64(32) })).status, 410);
    assert.equal((await join(p)).status, 200);
    assert.equal((await join(p)).status, 410);
    assert.equal((await call(p.path, null, stranger.token)).status, 410);
    assert.equal((await call(p.path + "/approve", { device_id: p.device.device_id }, stranger.token)).status, 410);
    const waiting = await claim(p);
    assert.deepEqual(waiting, { status: 200, data: { state: "waiting" } });
    assert.equal((await call(p.path + "/claim", { poll_key: b64(32) })).status, 410);
    const pending = await call(p.path, null, owner.token);
    assert.equal(pending.data.target_device_id, p.device.device_id);
    assert.equal(pending.data.encrypted_dek, undefined);
    assert.equal((await call(p.path + "/approve", { device_id: randomUUID() }, owner.token)).status, 410);
    assert.equal((await call(p.path + "/approve", { device_id: p.device.device_id }, owner.token)).status, 204);
    const claims = await Promise.all([claim(p), claim(p)]);
    assert.deepEqual(claims.map(r => r.status).sort(), [200, 410]);
    const paired = claims.find(r => r.status === 200).data;
    assert.equal(paired.state, "paired"); assert.equal(paired.encrypted_dek, p.encrypted);
    assert.equal(paired.account_id, owner.id); assert.equal(paired.handle, owner.handle);
    const devices = await call("devices", null, paired.token);
    assert.equal(devices.status, 200);
    assert.equal(devices.data.devices.find(d => d.current).device_id, p.device.device_id);
    assert.equal((await claim(p)).status, 410);

    const cancelled = await invite(owner); await join(cancelled);
    await call(cancelled.path + "/cancel", { poll_key: b64(32) });
    assert.equal((await claim(cancelled)).status, 200); // wrong proof cannot cancel
    await call(cancelled.path + "/cancel", { poll_key: cancelled.poll });
    assert.equal((await claim(cancelled)).status, 410);

    const denied = await invite(owner); await join(denied);
    await call(denied.path, null, owner.token, "DELETE");
    assert.equal((await claim(denied)).status, 410);

    const expired = await invite(owner);
    await sql`UPDATE device_pairings SET expires_at=now()-interval '1 second' WHERE pairing_id=${expired.id}`;
    assert.equal((await join(expired)).status, 410);

    const stale = await invite(owner); await join(stale);
    await call(stale.path + "/approve", { device_id: stale.device.device_id }, owner.token);
    await sql`UPDATE accounts SET auth_verifier=decode(repeat('01',32),'hex') WHERE account_id=${owner.id}`;
    assert.equal((await claim(stale)).status, 410);
    await sql`UPDATE accounts SET auth_verifier=decode(${Buffer.from(hash(owner.auth), "base64url").toString("hex")},'hex') WHERE account_id=${owner.id}`;

    const loggedOut = await invite(owner); await join(loggedOut);
    await call(loggedOut.path + "/approve", { device_id: loggedOut.device.device_id }, owner.token);
    await call("sessions/current", null, owner.token, "DELETE");
    assert.equal((await claim(loggedOut)).status, 410);
    const again = await call("sessions", { handle: owner.handle, auth_key: owner.auth, device: { device_id: randomUUID(), priority: 4 } });
    owner.token = again.data.token;
  } finally {
    for (const a of [owner, stranger]) await call("account", { handle: a.handle, auth_key: a.auth }, a.token, "DELETE");
  }
});
