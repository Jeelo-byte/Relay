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
      handle = "test_" + randomBytes(7).toString("hex");
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
      recovery_verifier: hash(randomBytes(32)),
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
  },
);
