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
      ["prelogin", "accounts", "sessions"].includes(path) &&
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
    async function newSession(account, device) {
      const token = randomBytes(32).toString("base64url");
      const expires = new Date(Date.now() + 30 * 86400000).toISOString();
      const existing =
        await sql`SELECT account_id,revoked_at FROM devices WHERE device_id=${device.device_id}`;
      if (
        existing.length &&
        (existing[0].account_id !== account || existing[0].revoked_at)
      )
        fail(
          401,
          "device_revoked",
          "This device was removed. Sign in with a new device identity.",
        );
      await sql.transaction([
        sql`INSERT INTO devices(device_id,account_id,priority,last_seen_at) VALUES(${device.device_id},${account},${device.priority},now()) ON CONFLICT(device_id) DO UPDATE SET last_seen_at=now(),priority=excluded.priority`,
        sql`INSERT INTO sessions(token_hash,account_id,device_id,expires_at) VALUES(${bytea(hash(Buffer.from(token)))},${account},${device.device_id},${expires})`,
      ]);
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
      return respond(await newSession(body.account_id, body.device), 201);
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
        ...(await newSession(a.account_id, body.device)),
        account_id: a.account_id,
        wraps: wraps.map((w) => ({
          ...w,
          wrapped_dek: Buffer.from(w.wrapped_dek).toString("base64url"),
        })),
      });
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
