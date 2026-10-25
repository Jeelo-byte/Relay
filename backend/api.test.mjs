import test from "node:test";
import assert from "node:assert/strict";
import { randomUUID, randomBytes, createHash } from "node:crypto";
import { handleAPI, validHandle } from "./api.mjs";
const env = !!process.env.DATABASE_URL;
const hash = (b) => createHash("sha256").update(b).digest("base64url");
async function request(path, method = "GET", body, token) {
  return handleAPI(
    new Request("http://localhost/api/v1/" + path, {
      method,
      headers: {
        "content-type": "application/json",
        "x-forwarded-for": testIP,
        ...(token ? { authorization: "Bearer " + token } : {}),
      },
      ...(body ? { body: JSON.stringify(body) } : {}),
    }),
  );
}
const testIP = randomUUID();
test("handle validation rejects email and malformed identity", () => {
  assert.equal(validHandle("relay_demo"), true);
  assert.equal(validHandle("a@b.com"), false);
  assert.equal(validHandle("ab"), false);
  assert.equal(validHandle("../user"), false);
});
test(
  "live Neon API: account, authentication, optimistic writes, leases, ciphertext audit",
  { skip: !env },
  async () => {
    const auth = randomBytes(32),
      account = randomUUID(),
      device = randomUUID(),
      handle = "test_" + randomBytes(7).toString("hex"),
      recoveryProof = randomBytes(32);
    const wraps = ["passphrase", "recovery"].map((w) => ({
      key_version: 1,
      wrap_type: w,
      wrapped_dek: randomBytes(60).toString("base64url"),
    }));
    const signup = await request("accounts", "POST", {
      account_id: account,
      handle,
      kdf_salt: randomBytes(16).toString("base64url"),
      kdf_params: { mem: 67108864, ops: 3, alg: "argon2id13" },
      auth_verifier: hash(auth),
      recovery_verifier: hash(recoveryProof),
      wraps,
      device: { device_id: device, priority: 4 },
    });
    assert.equal(signup.status, 201, await signup.clone().text());
    const { token } = await signup.json();
    const unknown = await request("blobs");
    assert.equal(unknown.status, 401);
    const wrong = await request("sessions", "POST", {
      handle,
      auth_key: randomBytes(32).toString("base64url"),
      device: { device_id: randomUUID(), priority: 1 },
    });
    assert.equal(wrong.status, 401);
    const login = await request("sessions", "POST", {
      handle,
      auth_key: auth.toString("base64url"),
      device: { device_id: randomUUID(), priority: 1 },
    });
    assert.equal(login.status, 200);
    const otherSession = await login.json();
    const devices = await (await request("devices", "GET", null, token)).json();
    assert.equal(devices.devices.length, 2);
    assert.equal(devices.devices.find((d) => d.device_id === device).current, true);
    const otherDevice = devices.devices.find((d) => !d.current).device_id;
    assert.equal((await request("devices/" + otherDevice, "DELETE", { auth_key: randomBytes(32).toString("base64url") }, token)).status, 401);
    assert.equal((await request("devices/" + randomUUID(), "DELETE", { auth_key: auth.toString("base64url") }, token)).status, 404);
    assert.equal((await request("devices/" + otherDevice, "DELETE", { auth_key: auth.toString("base64url") }, token)).status, 204);
    assert.equal((await request("blobs", "GET", null, otherSession.token)).status, 401);
    const revokedLogin = await request("sessions", "POST", { handle, auth_key: auth.toString("base64url"), device: { device_id: otherDevice, priority: 1 } });
    assert.equal(revokedLogin.status, 401);
    const row = randomUUID(),
      envelope = Buffer.concat([
        Buffer.from([1, 0, 0, 0, 1]),
        randomBytes(540),
      ]).toString("base64url");
    const created = await request(
      "blobs/" + row,
      "PUT",
      { base_version: 0, key_version: 1, envelope },
      token,
    );
    assert.equal(created.status, 200);
    assert.equal((await created.json()).version, 1);
    const conflict = await request(
      "blobs/" + row,
      "PUT",
      { base_version: 0, key_version: 1, envelope },
      token,
    );
    assert.equal(conflict.status, 409);
    assert.equal((await conflict.json()).current.version, 1);
    const pulled = await request("blobs?since=0", "GET", null, token),
      result = await pulled.json();
    assert.equal(result.items[0].envelope, envelope);
    assert.equal(result.items[0].row_id, row);
    assert.equal(JSON.stringify(result).includes("RELAYCANARY"), false);
    const lease = randomBytes(32).toString("base64url"),
      held = await request(
        "leases/acquire",
        "POST",
        { lease_key: lease, ttl_s: 180 },
        token,
      );
    assert.equal((await held.json()).granted, true);
    await request("leases/complete", "POST", { lease_key: lease }, token);
    const repeated = await request(
      "leases/acquire",
      "POST",
      { lease_key: lease, ttl_s: 180 },
      token,
    );
    assert.equal((await repeated.json()).state, "done");
    const removed = await request(
      "blobs/" + row,
      "DELETE",
      { base_version: 1 },
      token,
    );
    assert.equal(removed.status, 200);
    const resurrection = await request(
      "blobs/" + row,
      "PUT",
      { base_version: 2, key_version: 1, envelope },
      token,
    );
    assert.equal(resurrection.status, 409);
    assert.equal((await resurrection.json()).current.deleted, true);
    const beforeRotation = await (await request("sessions", "POST", {
      handle, auth_key: auth.toString("base64url"), device: { device_id: randomUUID(), priority: 2 },
    })).json();
    const nextAuth = randomBytes(32), nextSalt = randomBytes(16).toString("base64url"), nextWrap = randomBytes(60).toString("base64url");
    const replacement = { auth_key: auth.toString("base64url"), auth_verifier: hash(nextAuth),
      kdf_salt: nextSalt, kdf_params: { alg: "argon2id13", ops: 3, mem: 67108864 }, wrapped_dek: nextWrap };
    assert.equal((await request("account/passphrase", "PUT", { ...replacement, kdf_salt: "bad" }, token)).status, 400);
    assert.equal((await request("account/passphrase", "PUT", { ...replacement, auth_key: randomBytes(32).toString("base64url") }, token)).status, 401);
    assert.equal((await request("account/passphrase", "PUT", replacement, token)).status, 204);
    assert.equal((await request("blobs", "GET", null, beforeRotation.token)).status, 401);
    assert.equal((await request("blobs", "GET", null, token)).status, 200);
    assert.equal((await request("account/passphrase", "PUT", replacement, token)).status, 401, "A stale proof must not overwrite the new credential");
    const prelogin = await (await request("prelogin?handle=" + handle)).json();
    assert.equal(prelogin.kdf_salt, nextSalt);
    assert.equal((await request("sessions", "POST", { handle, auth_key: auth.toString("base64url"), device: { device_id: randomUUID(), priority: 1 } })).status, 401);
    const afterRotation = await request("sessions", "POST", { handle, auth_key: nextAuth.toString("base64url"), device: { device_id: randomUUID(), priority: 1 } });
    assert.equal(afterRotation.status, 200);
    const updatedWraps = (await afterRotation.json()).wraps;
    assert.equal(updatedWraps.find((w) => w.wrap_type === "passphrase").wrapped_dek, nextWrap);
    assert.equal(updatedWraps.find((w) => w.wrap_type === "recovery").wrapped_dek, wraps[1].wrapped_dek);
    const recoveryPreflight = await (await request("recovery/preflight?handle=" + handle)).json();
    assert.equal(recoveryPreflight.account_id, account);
    assert.equal(recoveryPreflight.wrapped_dek, wraps[1].wrapped_dek);
    const fake1 = await (await request("recovery/preflight?handle=unknown_" + randomUUID().slice(0,8))).json();
    assert.equal(Buffer.from(fake1.wrapped_dek, "base64url").length, 60);
    assert.deepEqual(Object.keys(fake1).sort(), Object.keys(recoveryPreflight).sort());
    const resetProof = randomBytes(32), resetAuth = randomBytes(32);
    const resetWraps = wraps.map((w) => ({ ...w, wrapped_dek: randomBytes(60).toString("base64url") }));
    const reset = { handle, account_id: account, recovery_proof: recoveryProof.toString("base64url"),
      auth_verifier: hash(resetAuth), recovery_verifier: hash(resetProof), kdf_salt: randomBytes(16).toString("base64url"),
      kdf_params: { alg: "argon2id13", ops: 3, mem: 67108864 }, wraps: resetWraps, device: { device_id: randomUUID(), priority: 4 } };
    assert.equal((await request("recovery/reset", "POST", { ...reset, recovery_proof: randomBytes(32).toString("base64url") })).status, 401);
    assert.equal((await request("recovery/reset", "POST", { ...reset, device: { device_id: device, priority: 4 } })).status, 401, "Recovery requires a new device identity");
    const recovered = await request("recovery/reset", "POST", reset);
    assert.equal(recovered.status, 200, await recovered.clone().text());
    const recoveredToken = (await recovered.json()).token;
    assert.equal((await request("blobs", "GET", null, token)).status, 401);
    const recoveredBlobs = await (await request("blobs", "GET", null, recoveredToken)).json();
    assert.equal(recoveredBlobs.items.find((r) => r.row_id === row).deleted, true);
    assert.equal((await request("recovery/reset", "POST", { ...reset, device: { device_id: randomUUID(), priority: 2 } })).status, 401, "Old recovery proof must not be reusable");
    const recoveredLogin = await request("sessions", "POST", { handle, auth_key: resetAuth.toString("base64url"), device: { device_id: randomUUID(), priority: 1 } });
    assert.equal(recoveredLogin.status, 200);
    assert.equal((await recoveredLogin.json()).wraps.find((w) => w.wrap_type === "recovery").wrapped_dek, resetWraps[1].wrapped_dek);
    assert.equal((await request("account", "DELETE", { handle: "wrong_handle", auth_key: resetAuth.toString("base64url") }, recoveredToken)).status, 401);
    assert.equal((await request("account", "DELETE", { handle, auth_key: randomBytes(32).toString("base64url") }, recoveredToken)).status, 401);
    assert.equal((await request("blobs", "GET", null, recoveredToken)).status, 200);
    assert.equal((await request("account", "DELETE", { handle, auth_key: resetAuth.toString("base64url") }, recoveredToken)).status, 204);
    assert.equal((await request("blobs", "GET", null, recoveredToken)).status, 401);
    assert.equal((await request("sessions", "POST", { handle, auth_key: resetAuth.toString("base64url"), device: { device_id: randomUUID(), priority: 1 } })).status, 401);
  },
);
