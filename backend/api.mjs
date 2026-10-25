import { neon } from "@neondatabase/serverless";
import {
  createHash,
  createHmac,
  randomBytes,
  randomUUID,
  timingSafeEqual,
} from "node:crypto";
const hash = (x) => createHash("sha256").update(x).digest();
const decode = (x) => Buffer.from(x || "", "base64url");
const hex = (x) => Buffer.from(x).toString("hex");
const uuid = (x) =>
  typeof x === "string" &&
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(x);
export const validHandle = (x) =>
  typeof x === "string" && /^[a-z0-9_]{3,32}$/.test(x);
class APIError extends Error {
  constructor(status, code, message, retryable = false) {
    super(message);
    Object.assign(this, { status, code, retryable });
  }
}
const fail = (s, c, m, r = false) => {
  throw new APIError(s, c, m, r);
};
const bytea = (x) => "\\x" + hex(x);
const equal = (a, b) => a.length === b.length && timingSafeEqual(a, b);
function blob(row) {
  return {
    ...row,
    envelope: row.envelope
      ? Buffer.from(row.envelope).toString("base64url")
      : null,
    seq: Number(row.seq),
  };
}
function validDevice(d) {
  return d && uuid(d.device_id) && [1, 2, 3, 4].includes(d.priority);
}
function validateWraps(w) {
  return (
    Array.isArray(w) &&
    w.length === 2 &&
    new Set(w.map((x) => x.wrap_type)).size === 2 &&
    w.every(
      (x) =>
        x.key_version === 1 &&
        ["passphrase", "recovery"].includes(x.wrap_type) &&
        decode(x.wrapped_dek).length === 60,
    )
  );
}
export async function handleAPI(request) {
  const headers = {
    "Content-Type": "application/json",
    "Cache-Control": "no-store",
    "Referrer-Policy": "no-referrer",
    "X-Content-Type-Options": "nosniff",
  };
  const respond = (body, status = 200) =>
    new Response(status === 204 ? null : JSON.stringify(body), {
      status,
      headers,
    });
  try {
    if (!process.env.DATABASE_URL)
      fail(503, "unavailable", "The database is not configured.", true);
    const sql = neon(process.env.DATABASE_URL),
      url = new URL(request.url),
      path = url.pathname.replace(/^\/api\/v1\/?/, "").replace(/\/$/, ""),
      method = request.method;
    if (path === "health") {
      const t = Date.now();
      await sql`SELECT 1`;
      return respond({ ok: true, db_ms: Date.now() - t });
    }
    const contentLength = Number(request.headers.get("content-length") || 0);
    if (contentLength > 150000) fail(413, "too_large", "Request is too large.");
    let body = {};
    if (["POST", "PUT", "DELETE"].includes(method)) {
      const text = await request.text();
      if (text.length > 150000) fail(413, "too_large", "Request is too large.");
      if (text) {
        try {
          body = JSON.parse(text);
        } catch {
          fail(400, "bad_request", "Invalid JSON.");
        }
      }
    }
    async function limit(scope, max, seconds) {
      const rows =
        await sql`INSERT INTO request_limits(scope,window_start,count) VALUES(${scope},now(),1) ON CONFLICT(scope) DO UPDATE SET count=CASE WHEN request_limits.window_start<now()-make_interval(secs=>${seconds}) THEN 1 ELSE request_limits.count+1 END,window_start=CASE WHEN request_limits.window_start<now()-make_interval(secs=>${seconds}) THEN now() ELSE request_limits.window_start END RETURNING count`;
      if (rows[0].count > max)
        fail(429, "rate_limited", "Too many attempts. Try again later.", true);
    }
    if (
      ["prelogin", "accounts", "sessions", "recovery/preflight", "recovery/reset"].includes(path) &&
      method !== "DELETE"
    ) {
      // IP headers are trusted only behind the hosting proxy. Hash before persistence.
      const ip =
        request.headers.get("x-forwarded-for")?.split(",")[0] || "local";
      await limit(
        hash(Buffer.from(ip)).toString("hex") + ":" + path,
        path === "accounts" ? 5 : 60,
        3600,
      );
    }
    if (path === "prelogin" && method === "GET") {
      const handle = (url.searchParams.get("handle") || "").toLowerCase();
      if (!validHandle(handle))
        fail(400, "bad_request", "Use 3–32 letters, numbers or underscores.");
      const rows =
        await sql`SELECT kdf_salt,kdf_params FROM accounts WHERE handle=${handle}`;
      const secret = process.env.PRELOGIN_HMAC_SECRET;
      if (!secret)
        fail(503, "unavailable", "Account security is not configured.");
      return respond({
        kdf_salt: rows[0]
          ? Buffer.from(rows[0].kdf_salt).toString("base64url")
          : createHmac("sha256", secret)
              .update(handle)
              .digest()
              .subarray(0, 16)
              .toString("base64url"),
        kdf_params: rows[0]?.kdf_params || {
          alg: "argon2id13",
          ops: 3,
          mem: 67108864,
        },
      });
    }
    if (path === "recovery/preflight" && method === "GET") {
      const handle = (url.searchParams.get("handle") || "").toLowerCase();
      if (!validHandle(handle)) fail(400, "bad_request", "Use your Relay handle.");
      const secret = process.env.PRELOGIN_HMAC_SECRET;
      if (!secret) fail(503, "unavailable", "Account security is not configured.");
      const [row] = await sql`SELECT a.account_id,w.wrapped_dek FROM accounts a JOIN key_wraps w USING(account_id)
        WHERE a.handle=${handle} AND w.wrap_type='recovery' AND w.key_version=1`;
      // Unknown handles return the same response shape and deterministic fake material.
      const fake = (label) => createHmac("sha512", secret).update(label + "|" + handle).digest();
      const id = fake("recovery-id").subarray(0,16); id[6] = (id[6] & 15) | 64; id[8] = (id[8] & 63) | 128;
      const h = id.toString("hex"), fakeID = `${h.slice(0,8)}-${h.slice(8,12)}-${h.slice(12,16)}-${h.slice(16,20)}-${h.slice(20)}`;
      return respond({ account_id: row?.account_id || fakeID,
        wrapped_dek: row ? Buffer.from(row.wrapped_dek).toString("base64url") : fake("recovery-wrap").subarray(0,60).toString("base64url") });
    }
    if (path === "recovery/reset" && method === "POST") {
      if (!validHandle(body.handle) || !uuid(body.account_id) || !validDevice(body.device) ||
        decode(body.recovery_proof).length !== 32 || decode(body.auth_verifier).length !== 32 ||
        decode(body.recovery_verifier).length !== 32 || decode(body.kdf_salt).length !== 16 || !validateWraps(body.wraps) ||
        body.kdf_params?.alg !== "argon2id13" || body.kdf_params?.ops !== 3 || body.kdf_params?.mem !== 67108864)
        fail(400, "bad_request", "Invalid recovery parameters.");
      await limit(hash(Buffer.from(body.handle)).toString("hex") + ":recovery", 10, 3600);
      const token = randomBytes(32).toString("base64url");
      const passWrap = body.wraps.find((w) => w.wrap_type === "passphrase");
      const recoveryWrap = body.wraps.find((w) => w.wrap_type === "recovery");
      const rows = await sql`WITH changed AS (
        UPDATE accounts SET kdf_salt=${bytea(decode(body.kdf_salt))},kdf_params=${JSON.stringify(body.kdf_params)},
          auth_verifier=${bytea(decode(body.auth_verifier))},recovery_verifier=${bytea(decode(body.recovery_verifier))},failed_logins=0,locked_until=NULL
        WHERE account_id=${body.account_id} AND handle=${body.handle}
          AND recovery_verifier=${bytea(hash(decode(body.recovery_proof)))}
          AND NOT EXISTS (SELECT 1 FROM devices WHERE device_id=${body.device.device_id})
        RETURNING account_id
      ), wraps AS (
        UPDATE key_wraps SET wrapped_dek=CASE WHEN wrap_type='passphrase' THEN ${bytea(decode(passWrap.wrapped_dek))}::bytea ELSE ${bytea(decode(recoveryWrap.wrapped_dek))}::bytea END
        WHERE account_id IN (SELECT account_id FROM changed) AND key_version=1 RETURNING id
      ), expired AS (
        DELETE FROM sessions WHERE account_id IN (SELECT account_id FROM changed) RETURNING token_hash
      ), revoked AS (
        UPDATE devices SET revoked_at=COALESCE(revoked_at,now()) WHERE account_id IN (SELECT account_id FROM changed) RETURNING device_id
      ), released AS (
        DELETE FROM leases WHERE account_id IN (SELECT account_id FROM changed) RETURNING lease_key
      ), device AS (
        INSERT INTO devices(device_id,account_id,priority,last_seen_at)
        SELECT ${body.device.device_id},account_id,${body.device.priority},now() FROM changed RETURNING account_id,device_id
      ), fresh AS (
        INSERT INTO sessions(token_hash,account_id,device_id,expires_at)
        SELECT ${bytea(hash(Buffer.from(token)))},account_id,device_id,now()+interval '30 days' FROM device RETURNING account_id
      ) SELECT account_id FROM fresh`;
      if (!rows.length) fail(401, "bad_recovery", "Handle or recovery code is incorrect, or this recovery code was already replaced.");
      return respond({ token, account_id: rows[0].account_id });
    }
    async function newSession(account, device, verifier) {
      const token = randomBytes(32).toString("base64url");
      const expires = new Date(Date.now() + 30 * 86400000).toISOString();
      // Serialize sign-in with recovery, credential changes, and deletion. A
      // password verified before a reset cannot mint a session after that reset.
      const rows = await sql`WITH authorized AS (
        SELECT account_id FROM accounts WHERE account_id=${account} AND auth_verifier=${bytea(verifier)} FOR UPDATE
      ), device AS (
        INSERT INTO devices(device_id,account_id,priority,last_seen_at)
        SELECT ${device.device_id},account_id,${device.priority},now() FROM authorized
        ON CONFLICT(device_id) DO UPDATE SET last_seen_at=now(),priority=excluded.priority
          WHERE devices.account_id=excluded.account_id AND devices.revoked_at IS NULL
        RETURNING account_id,device_id
      ) INSERT INTO sessions(token_hash,account_id,device_id,expires_at)
        SELECT ${bytea(hash(Buffer.from(token)))},account_id,device_id,${expires}::timestamptz FROM device RETURNING account_id`;
      if (!rows.length) fail(401, "credentials_changed", "Your credentials changed or this device was removed. Sign in again with a new device identity.");
      return { token, expires_at: expires };
    }
    if (path === "accounts" && method === "POST") {
      if (
        !uuid(body.account_id) ||
        !validHandle(body.handle) ||
        decode(body.kdf_salt).length !== 16 ||
        decode(body.auth_verifier).length !== 32 ||
        decode(body.recovery_verifier).length !== 32 ||
        !validDevice(body.device) ||
        !validateWraps(body.wraps) ||
        body.kdf_params?.alg !== "argon2id13" ||
        body.kdf_params?.ops !== 3 ||
        body.kdf_params?.mem !== 67108864
      )
        fail(400, "bad_request", "Invalid account parameters.");
      try {
        await sql.transaction([
          sql`INSERT INTO accounts(account_id,handle,kdf_salt,kdf_params,auth_verifier,recovery_verifier) VALUES(${body.account_id},${body.handle},${bytea(decode(body.kdf_salt))},${JSON.stringify(body.kdf_params)},${bytea(decode(body.auth_verifier))},${bytea(decode(body.recovery_verifier))})`,
          ...body.wraps.map(
            (w) =>
              sql`INSERT INTO key_wraps(id,account_id,key_version,wrap_type,wrapped_dek) VALUES(${randomUUID()},${body.account_id},${w.key_version},${w.wrap_type},${bytea(decode(w.wrapped_dek))})`,
          ),
        ]);
      } catch (e) {
        if (e.code === "23505")
          fail(409, "handle_taken", "That handle is taken. Choose another.");
        throw e;
      }
      return respond(await newSession(body.account_id, body.device, decode(body.auth_verifier)), 201);
    }
    if (path === "sessions" && method === "POST") {
      if (
        !validHandle(body.handle) ||
        decode(body.auth_key).length !== 32 ||
        !validDevice(body.device)
      )
        fail(401, "bad_credentials", "Handle or passphrase is incorrect.");
      const [a] = await sql`SELECT * FROM accounts WHERE handle=${body.handle}`;
      if (a?.locked_until && new Date(a.locked_until) > new Date())
        fail(429, "locked", "Too many attempts. Try again shortly.", true);
      if (
        !a ||
        !equal(hash(decode(body.auth_key)), Buffer.from(a.auth_verifier))
      ) {
        if (a)
          await sql`UPDATE accounts SET failed_logins=failed_logins+1,locked_until=CASE WHEN failed_logins>=4 THEN now()+make_interval(secs=>LEAST(900,30*power(2,failed_logins-4))::int) ELSE NULL END WHERE account_id=${a.account_id}`;
        fail(401, "bad_credentials", "Handle or passphrase is incorrect.");
      }
      await sql`UPDATE accounts SET failed_logins=0,locked_until=NULL WHERE account_id=${a.account_id}`;
      const wraps =
        await sql`SELECT key_version,wrap_type,wrapped_dek FROM key_wraps WHERE account_id=${a.account_id}`;
      return respond({
        ...(await newSession(a.account_id, body.device, Buffer.from(a.auth_verifier))),
        account_id: a.account_id,
        wraps: wraps.map((w) => ({
          ...w,
          wrapped_dek: Buffer.from(w.wrapped_dek).toString("base64url"),
        })),
      });
    }
    const pairingRoute = path.match(/^pairings\/([0-9a-f-]+)(?:\/(join|claim|cancel|approve))?$/i);
    if (pairingRoute && !uuid(pairingRoute[1])) fail(400, "bad_request", "Invalid pairing code.");
    // The scanned secret never reaches the API: only its hash and an encrypted DEK.
    // A separate, unshared poll secret binds redemption to the device that joined.
    if (pairingRoute && method === "POST" && ["join", "claim", "cancel"].includes(pairingRoute[2])) {
      const [, id, action] = pairingRoute;
      const ip = request.headers.get("x-forwarded-for")?.split(",")[0] || "local";
      await limit(hash(Buffer.from(ip)).toString("hex") + ":pairing:" + action, action === "join" ? 30 : 1000, 600);
      if (action === "join") {
        if (!validDevice(body.device) || decode(body.key_hash).length !== 32 || decode(body.poll_hash).length !== 32)
          fail(400, "bad_request", "Invalid pairing request.");
        const rows = await sql`UPDATE device_pairings p SET target_device_id=${body.device.device_id},
          target_priority=${body.device.priority},poll_hash=${bytea(decode(body.poll_hash))}
          WHERE pairing_id=${id} AND key_hash=${bytea(decode(body.key_hash))} AND expires_at>now()
            AND target_device_id IS NULL
            AND NOT EXISTS (SELECT 1 FROM devices WHERE device_id=${body.device.device_id})
            AND EXISTS (SELECT 1 FROM sessions s JOIN devices d USING(device_id) JOIN accounts a ON a.account_id=s.account_id
              WHERE s.token_hash=p.creator_session_hash AND s.expires_at>now() AND d.revoked_at IS NULL AND a.auth_verifier=p.auth_verifier)
          RETURNING expires_at`;
        if (!rows.length) fail(410, "pairing_unavailable", "This code expired or was already scanned. Show a new code on your other device.");
        return respond({ state: "waiting", expires_at: rows[0].expires_at });
      }
      if (decode(body.poll_key).length !== 32) fail(400, "bad_request", "Invalid pairing request.");
      const proof = bytea(hash(decode(body.poll_key)));
      if (action === "cancel") {
        await sql`DELETE FROM device_pairings WHERE pairing_id=${id} AND poll_hash=${proof}`;
        return respond(null, 204);
      }
      const freshToken = randomBytes(32).toString("base64url");
      // Consume once and mint the device/session in one statement. Lock the account
      // as sign-in does so recovery/credential changes cannot revive old approval.
      const rows = await sql`WITH authorized AS (
        SELECT p.*,a.handle FROM accounts a JOIN device_pairings p USING(account_id)
        JOIN sessions s ON s.token_hash=p.creator_session_hash JOIN devices d ON d.device_id=s.device_id
        WHERE p.pairing_id=${id} AND p.poll_hash=${proof} AND p.expires_at>now() AND p.approved
          AND s.expires_at>now() AND d.revoked_at IS NULL AND a.auth_verifier=p.auth_verifier
          AND NOT EXISTS (SELECT 1 FROM devices WHERE device_id=p.target_device_id)
        FOR UPDATE OF a,p
      ), consumed AS (
        DELETE FROM device_pairings WHERE pairing_id IN (SELECT pairing_id FROM authorized) RETURNING pairing_id
      ), device AS (
        INSERT INTO devices(device_id,account_id,priority,last_seen_at)
        SELECT target_device_id,account_id,target_priority,now() FROM authorized
        WHERE pairing_id IN (SELECT pairing_id FROM consumed) RETURNING device_id,account_id
      ), fresh AS (
        INSERT INTO sessions(token_hash,account_id,device_id,expires_at)
        SELECT ${bytea(hash(Buffer.from(freshToken)))},account_id,device_id,now()+interval '30 days' FROM device RETURNING account_id
      ) SELECT a.account_id,a.handle,a.encrypted_dek FROM authorized a JOIN fresh USING(account_id)`;
      if (rows.length) return respond({ state: "paired", token: freshToken, account_id: rows[0].account_id,
        handle: rows[0].handle, encrypted_dek: Buffer.from(rows[0].encrypted_dek).toString("base64url") });
      const [pending] = await sql`SELECT p.pairing_id FROM device_pairings p JOIN sessions s ON s.token_hash=p.creator_session_hash
        JOIN devices d ON d.device_id=s.device_id JOIN accounts a ON a.account_id=p.account_id
        WHERE pairing_id=${id} AND poll_hash=${proof} AND p.expires_at>now() AND s.expires_at>now()
          AND d.revoked_at IS NULL AND a.auth_verifier=p.auth_verifier`;
      if (!pending) fail(410, "pairing_unavailable", "Pairing expired, was cancelled, or has finished. Scan a new code.");
      return respond({ state: "waiting" });
    }
    const token = request.headers.get("authorization")?.replace(/^Bearer /, "");
    if (!token) fail(401, "unauthorized", "Unlock Relay to continue.");
    const [session] =
      await sql`SELECT s.account_id,s.device_id,d.priority,d.revoked_at FROM sessions s JOIN devices d USING(device_id) WHERE s.token_hash=${bytea(hash(Buffer.from(token)))} AND s.expires_at>now()`;
    if (!session)
      fail(401, "unauthorized", "Your session expired. Sign in again.");
    if (session.revoked_at)
      fail(401, "device_revoked", "This device was removed.");
    const account = session.account_id;
    await sql`UPDATE sessions SET expires_at=now()+interval '30 days' WHERE token_hash=${bytea(hash(Buffer.from(token)))}`;
    if (path === "sessions/current" && method === "DELETE") {
      await sql`DELETE FROM sessions WHERE token_hash=${bytea(hash(Buffer.from(token)))}`;
      return respond(null, 204);
    }
    if (path === "pairings" && method === "POST") {
      await limit(account + ":pairing-create", 30, 3600);
      if (!uuid(body.pairing_id) || decode(body.key_hash).length !== 32 || decode(body.encrypted_dek).length !== 60)
        fail(400, "bad_request", "Invalid pairing code.");
      await sql`DELETE FROM device_pairings WHERE expires_at<=now()`;
      const [created] = await sql`INSERT INTO device_pairings(pairing_id,account_id,creator_session_hash,auth_verifier,key_hash,encrypted_dek)
        SELECT ${body.pairing_id},a.account_id,s.token_hash,a.auth_verifier,${bytea(decode(body.key_hash))},${bytea(decode(body.encrypted_dek))}
        FROM accounts a JOIN sessions s USING(account_id) JOIN devices d USING(device_id)
        WHERE a.account_id=${account} AND s.token_hash=${bytea(hash(Buffer.from(token)))} AND s.expires_at>now() AND d.revoked_at IS NULL
        RETURNING expires_at`;
      if (!created) fail(401, "unauthorized", "Unlock Relay again to pair a device.");
      return respond({ expires_at: created.expires_at }, 201);
    }
    if (pairingRoute) {
      const [, id, action] = pairingRoute;
      const [pair] = await sql`SELECT p.target_device_id,p.target_priority,p.approved,p.expires_at FROM device_pairings p
        JOIN accounts a USING(account_id) WHERE p.pairing_id=${id} AND p.account_id=${account}
          AND p.creator_session_hash=${bytea(hash(Buffer.from(token)))} AND p.expires_at>now() AND p.auth_verifier=a.auth_verifier`;
      if (!pair) fail(410, "pairing_unavailable", "This code has expired or pairing has finished. Show a new code to continue.");
      if (method === "GET" && !action) return respond(pair);
      if (method === "DELETE" && !action) {
        await sql`DELETE FROM device_pairings WHERE pairing_id=${id} AND account_id=${account}`;
        return respond(null, 204);
      }
      if (method === "POST" && action === "approve") {
        if (!uuid(body.device_id)) fail(400, "bad_request", "Choose the device to pair.");
        const rows = await sql`UPDATE device_pairings p SET approved=true
          WHERE pairing_id=${id} AND account_id=${account} AND target_device_id=${body.device_id} AND expires_at>now()
            AND EXISTS (SELECT 1 FROM sessions s JOIN devices d USING(device_id) JOIN accounts a ON a.account_id=s.account_id
              WHERE s.token_hash=p.creator_session_hash AND s.token_hash=${bytea(hash(Buffer.from(token)))}
                AND s.expires_at>now() AND d.revoked_at IS NULL AND a.auth_verifier=p.auth_verifier)
          RETURNING pairing_id`;
        if (!rows.length) fail(410, "pairing_unavailable", "That device is no longer waiting. Show a new code.");
        return respond(null, 204);
      }
    }
    if (path === "devices" && method === "GET") {
      const devices = await sql`SELECT device_id,priority,created_at,last_seen_at,revoked_at FROM devices WHERE account_id=${account} ORDER BY created_at`;
      return respond({ devices: devices.map((d) => ({ ...d, current: d.device_id === session.device_id })) });
    }
    if (path === "account/passphrase" && method === "PUT") {
      await limit(account + ":security", 10, 3600);
      if (decode(body.auth_key).length !== 32 || decode(body.auth_verifier).length !== 32 ||
        decode(body.kdf_salt).length !== 16 || decode(body.wrapped_dek).length !== 60 ||
        body.kdf_params?.alg !== "argon2id13" || body.kdf_params?.ops !== 3 || body.kdf_params?.mem !== 67108864)
        fail(400, "bad_request", "Invalid passphrase update parameters.");
      // Recheck both the proof and live session inside the atomic write. Concurrent
      // updates cannot silently replace a more recent credential or wrap.
      const changed = await sql`WITH changed AS (
        UPDATE accounts SET kdf_salt=${bytea(decode(body.kdf_salt))},kdf_params=${JSON.stringify(body.kdf_params)},
          auth_verifier=${bytea(decode(body.auth_verifier))},failed_logins=0,locked_until=NULL
        WHERE account_id=${account} AND auth_verifier=${bytea(hash(decode(body.auth_key)))}
          AND EXISTS (SELECT 1 FROM sessions s JOIN devices d USING(device_id)
            WHERE s.token_hash=${bytea(hash(Buffer.from(token)))} AND s.expires_at>now() AND d.revoked_at IS NULL)
        RETURNING account_id
      ), wrapped AS (
        UPDATE key_wraps SET wrapped_dek=${bytea(decode(body.wrapped_dek))}
        WHERE account_id IN (SELECT account_id FROM changed) AND wrap_type='passphrase' AND key_version=1 RETURNING id
      ), expired AS (
        DELETE FROM sessions WHERE account_id IN (SELECT account_id FROM changed)
          AND token_hash<>${bytea(hash(Buffer.from(token)))} RETURNING token_hash
      ), released AS (
        DELETE FROM leases WHERE account_id IN (SELECT account_id FROM changed) RETURNING lease_key
      ) SELECT account_id FROM changed`;
      if (!changed.length) fail(401, "bad_credentials", "Current passphrase is incorrect or your session changed. Unlock and try again.");
      return respond(null, 204);
    }
    if (path === "account" && method === "DELETE") {
      await limit(account + ":security", 10, 3600);
      if (!validHandle(body.handle) || decode(body.auth_key).length !== 32)
        fail(400, "bad_request", "Confirm your handle and current passphrase.");
      const removed = await sql`DELETE FROM accounts WHERE account_id=${account} AND handle=${body.handle}
        AND auth_verifier=${bytea(hash(decode(body.auth_key)))}
        AND EXISTS (SELECT 1 FROM sessions s JOIN devices d USING(device_id)
          WHERE s.token_hash=${bytea(hash(Buffer.from(token)))} AND s.expires_at>now() AND d.revoked_at IS NULL)
        RETURNING account_id`;
      if (!removed.length) fail(401, "bad_credentials", "Handle or current passphrase is incorrect, or your session changed.");
      return respond(null, 204);
    }
    const deviceMatch = path.match(/^devices\/([0-9a-f-]+)$/i);
    if (deviceMatch && method === "DELETE") {
      const device = deviceMatch[1];
      if (!uuid(device)) fail(400, "bad_request", "Invalid device identity.");
      await limit(account + ":security", 10, 3600);
      const [a] = await sql`SELECT auth_verifier FROM accounts WHERE account_id=${account}`;
      if (decode(body.auth_key).length !== 32 || !equal(hash(decode(body.auth_key)), Buffer.from(a.auth_verifier)))
        fail(401, "bad_credentials", "Confirm your current passphrase to remove a device.");
      const [target] = await sql`SELECT device_id FROM devices WHERE account_id=${account} AND device_id=${device}`;
      if (!target) fail(404, "not_found", "Device not found.");
      await sql.transaction([
        sql`UPDATE devices SET revoked_at=COALESCE(revoked_at,now()) WHERE account_id=${account} AND device_id=${device}`,
        sql`DELETE FROM sessions WHERE account_id=${account} AND device_id=${device}`,
        sql`DELETE FROM leases WHERE account_id=${account} AND holder_device_id=${device}`,
      ]);
      return respond(null, 204);
    }
    if (path === "blobs" && method === "GET") {
      const since = Number(url.searchParams.get("since") || 0),
        limit = Math.min(Number(url.searchParams.get("limit") || 500), 500);
      if (
        !Number.isSafeInteger(since) ||
        since < 0 ||
        !Number.isInteger(limit) ||
        limit < 1
      )
        fail(400, "bad_request", "Invalid cursor.");
      const rows =
        await sql`SELECT row_id,version,seq,key_version,envelope,deleted FROM blobs WHERE account_id=${account} AND seq>${since} ORDER BY seq LIMIT ${limit + 1}`;
      const items = rows.slice(0, limit).map(blob);
      return respond({
        items,
        next_since: items.at(-1)?.seq || since,
        has_more: rows.length > limit,
      });
    }
    async function put(row, op, deleted = false) {
      if (
        !uuid(row) ||
        !Number.isInteger(op.base_version) ||
        op.base_version < 0 ||
        (!deleted && (!Number.isInteger(op.key_version) || op.key_version < 1))
      )
        fail(400, "bad_request", "Invalid record.");
      const env = deleted ? null : decode(op.envelope);
      if (
        env &&
        (env.length > 98304 ||
          env.length < 33 ||
          env[0] !== 1 ||
          env.readUInt32BE(1) !== op.key_version)
      )
        fail(400, "bad_request", "Invalid encrypted envelope.");
      let rows;
      if (op.base_version === 0 && !deleted)
        rows =
          await sql`INSERT INTO blobs(account_id,row_id,version,key_version,envelope) VALUES(${account},${row},1,${op.key_version},${bytea(env)}) ON CONFLICT DO NOTHING RETURNING version,seq`;
      else
        rows =
          await sql`UPDATE blobs SET version=version+1,seq=nextval('blob_seq'),key_version=${op.key_version || 1},envelope=${env ? bytea(env) : null},deleted=${deleted},updated_at=now() WHERE account_id=${account} AND row_id=${row} AND version=${op.base_version} AND deleted=false RETURNING version,seq`;
      if (!rows.length) {
        const [current] =
          await sql`SELECT row_id,version,seq,key_version,envelope,deleted FROM blobs WHERE account_id=${account} AND row_id=${row}`;
        return { ok: false, conflict: current ? blob(current) : null };
      }
      return { ok: true, version: rows[0].version, seq: Number(rows[0].seq) };
    }
    if (
      path.startsWith("blobs/") &&
      ["PUT", "DELETE"].includes(method) &&
      path !== "blobs/batch"
    ) {
      const result = await put(path.split("/")[1], body, method === "DELETE");
      return result.ok
        ? respond(result)
        : respond({ current: result.conflict }, 409);
    }
    if (path === "blobs/batch" && method === "POST") {
      if (!Array.isArray(body.ops) || body.ops.length > 100)
        fail(400, "bad_request", "Send up to 100 records.");
      const results = [];
      for (const op of body.ops)
        results.push({
          row_id: op.row_id,
          ...(await put(op.row_id, op, op.envelope === null)),
        });
      return respond({ results });
    }
    if (path === "leases/acquire" && method === "POST") {
      if (decode(body.lease_key).length !== 32)
        fail(400, "bad_request", "Invalid lease.");
      const ttl = Math.max(1, Math.min(300, Number(body.ttl_s) || 180));
      const rows =
        await sql`INSERT INTO leases(account_id,lease_key,holder_device_id,priority,state,expires_at) VALUES(${account},${bytea(decode(body.lease_key))},${session.device_id},${session.priority},'held',now()+make_interval(secs=>${ttl})) ON CONFLICT(account_id,lease_key) DO UPDATE SET holder_device_id=excluded.holder_device_id,priority=excluded.priority,acquired_at=now(),expires_at=excluded.expires_at WHERE leases.state!='done' AND (leases.expires_at<now() OR (leases.priority<excluded.priority AND leases.acquired_at>now()-interval '5 seconds')) RETURNING *`;
      const row =
        rows[0] ||
        (
          await sql`SELECT * FROM leases WHERE account_id=${account} AND lease_key=${bytea(decode(body.lease_key))}`
        )[0];
      return respond({
        granted: rows.length > 0,
        holder_device_id: row.holder_device_id,
        state: row.state,
        expires_at: row.expires_at,
      });
    }
    if (path === "leases/complete" && method === "POST") {
      await sql`UPDATE leases SET state='done' WHERE account_id=${account} AND lease_key=${bytea(decode(body.lease_key))} AND holder_device_id=${session.device_id}`;
      return respond(null, 204);
    }
    if (path === "export") {
      const items =
        await sql`SELECT row_id,version,seq,key_version,envelope,deleted FROM blobs WHERE account_id=${account} ORDER BY seq`;
      const wraps =
        await sql`SELECT key_version,wrap_type,wrapped_dek FROM key_wraps WHERE account_id=${account}`;
      return respond({
        items: items.map(blob),
        wraps: wraps.map((w) => ({
          ...w,
          wrapped_dek: Buffer.from(w.wrapped_dek).toString("base64url"),
        })),
      });
    }
    fail(404, "not_found", "This endpoint does not exist.");
  } catch (e) {
    if (e instanceof APIError)
      return respond(
        { error: { code: e.code, message: e.message, retryable: e.retryable } },
        e.status,
      );
    return respond(
      {
        error: {
          code: "internal",
          message: "The service could not complete this request. Try again.",
          retryable: true,
        },
      },
      500,
    );
  }
}
