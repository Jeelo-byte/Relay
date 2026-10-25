import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { messageServer, roomInfo, mergeEvents, visibleMessages, mediaPath, sendMessage, matrixRequest, photoBlob } from "./matrix.js";

test("message server rejects credentials, insecure remote hosts, and HTTPS mixed content", () => {
  assert.equal(messageServer(" http://127.0.0.1:8008/ ", "http:"), "http://127.0.0.1:8008");
  assert.equal(messageServer("https://matrix.example.com", "https:"), "https://matrix.example.com");
  for (const url of ["http://192.168.1.2:8008", "https://user:pass@example.com", "https://example.com?token=secret", "file:///tmp/a"])
    assert.throws(() => messageServer(url, "http:"));
  assert.throws(() => messageServer("http://localhost:8008", "https:"), /HTTPS message server/);
});
test("incremental discovery retains encryption and member names", () => {
  const initial = roomInfo("!room", { state: { events: [
    { type: "m.room.name", content: { name: "Chosen chat" } },
    { type: "m.room.member", state_key: "@friend:test", content: { displayname: "Friend" } },
    { type: "m.room.encryption", content: {} },
  ] } }, "@me:test");
  const updated = roomInfo("!room", {}, "@me:test", initial);
  assert.equal(updated.encrypted, true);
  assert.equal(updated.members["@friend:test"], "Friend");
  assert.equal(updated.name, "Chosen chat");
});
const event = (id, sender, content, ts = 1) => ({ event_id: id, sender, content, type: "m.room.message", origin_server_ts: ts });
test("message updates deduplicate, authenticate edits, and preserve redactions across history reload", () => {
  const original = event("$1", "alice", { body: "original" });
  const edit = event("$2", "alice", { "m.relates_to": { rel_type: "m.replace", event_id: "$1" }, "m.new_content": { body: "corrected" } }, 2);
  const forged = event("$3", "bob", { "m.relates_to": { rel_type: "m.replace", event_id: "$1" }, "m.new_content": { body: "forged" } }, 3);
  let merged = mergeEvents([original], [original, edit, forged]);
  assert.equal(visibleMessages(merged).length, 1);
  assert.equal(visibleMessages(merged)[0].content.body, "corrected");
  merged = mergeEvents(merged, [{ event_id: "$4", type: "m.room.redaction", content: { redacts: "$1" }, origin_server_ts: 4 }]);
  merged = mergeEvents(merged, [original]);
  assert.equal(merged.find(e => e.event_id === "$1").unsigned.redacted_because, true);
  assert.equal(visibleMessages(merged)[0].content.body, undefined);
});
test("media addresses cannot change the homeserver request destination", () => {
  assert.equal(mediaPath("mxc://relay.local/abc_123"), "v1/media/download/relay.local/abc_123");
  for (const value of ["https://evil.test/photo", "mxc://user:password@host/a", "mxc://host/../a", "mxc://host/a?token=x"])
    assert.throws(() => mediaPath(value));
});
test("send rechecks encryption and withdrawn consent; retry keeps the transaction ID", async () => {
  const originalFetch = globalThis.fetch, calls = [], session = { server: "https://matrix.test", access_token: "fixture" };
  let encrypted = true, allowed = true;
  globalThis.fetch = async (url, options) => {
    calls.push([url, options]);
    return Response.json(url.endsWith("/state") ? (encrypted ? [{ type: "m.room.encryption" }] : []) : { event_id: "$sent" });
  };
  try {
    const room = { id: "!r:test", encrypted: false }, signal = new AbortController().signal;
    await assert.rejects(() => sendMessage(session, room, "hello", "same-id", signal), /encrypted/);
    assert.equal(calls.length, 1);
    encrypted = false;
    await assert.rejects(() => sendMessage(session, room, "hello", "same-id", signal, () => { const result = allowed; allowed = false; return result; }), /access changed/);
    assert.equal(calls.length, 2);
    await sendMessage(session, room, "hello", "same-id", signal);
    await sendMessage(session, room, "hello", "same-id", signal);
    assert.equal(calls[3][0], calls[5][0]);
    assert.equal(calls[3][1].headers.Authorization, "Bearer fixture");
  } finally { globalThis.fetch = originalFetch; }
});
test("photos reject oversized responses before buffering", async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => new Response(new Uint8Array(1), { headers: { "content-type": "image/png", "content-length": String(21 * 1024 * 1024) } });
  try {
    await assert.rejects(() => photoBlob({ server: "https://matrix.test", access_token: "fixture" }, "mxc://relay.local/a", new AbortController().signal), /20 MB/);
  } finally { globalThis.fetch = originalFetch; }
});
test("live local Matrix: authenticated discovery and opted-in room read (no sending)", { skip: process.env.RELAY_LIVE_MATRIX !== "1" }, async () => {
  const session = JSON.parse(await readFile(new URL("../../../infra/matrix/private/relay-account.json", import.meta.url)));
  const fixture = JSON.parse(await readFile(new URL("../../../infra/matrix/private/live-test.json", import.meta.url)));
  const who = await matrixRequest(session, "v3/account/whoami");
  assert.equal(who.user_id, session.user_id);
  const filter = { room: { rooms: [fixture.test_room_id], timeline: { limit: 10 } } };
  const result = await matrixRequest(session, "v3/sync?timeout=0&filter=" + encodeURIComponent(JSON.stringify(filter)));
  assert.ok(result.next_batch);
  const room = result.rooms.join[fixture.test_room_id];
  assert.ok(room);
  assert.ok(visibleMessages(mergeEvents([], room.timeline.events)).length);
});
