// Matrix traffic goes directly from the browser to the chosen homeserver.
// Tokens and chat text are never sent to the Relay agreement API.
export function messageServer(value, pageProtocol = globalThis.location?.protocol) {
  let url;
  try { url = new URL(value.trim()); } catch { throw Error("Enter your message server’s full address."); }
  const loopback = ["localhost", "127.0.0.1", "[::1]"].includes(url.hostname);
  if (url.username || url.password || url.search || url.hash ||
      (url.protocol !== "https:" && !(url.protocol === "http:" && loopback)))
    throw Error("Use HTTPS, or http://127.0.0.1:8008 on this Mac.");
  if (pageProtocol === "https:" && url.protocol !== "https:")
    throw Error("This HTTPS website needs an HTTPS message server. See the setup guide.");
  return url.href.replace(/\/$/, "");
}
export async function matrixRequest(session, path, { method = "GET", body, signal } = {}) {
  let response;
  try {
    response = await fetch(`${session.server}/_matrix/client/${path}`, {
      method, signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(35000)]) : AbortSignal.timeout(35000),
      cache: "no-store", credentials: "omit", referrerPolicy: "no-referrer",
      headers: { ...(body ? { "Content-Type": "application/json" } : {}),
        ...(session.access_token ? { Authorization: `Bearer ${session.access_token}` } : {}) },
      ...(body ? { body: JSON.stringify(body) } : {}),
    });
  } catch (error) {
    if (signal?.aborted) throw error;
    throw Error("Cannot reach the message server. Check Docker, the server address, and browser network access.");
  }
  const result = await response.json();
  if (!response.ok) {
    const error = Error(result.error || "The message server could not complete the request.");
    error.status = response.status;
    error.retryAfter = result.retry_after_ms;
    throw error;
  }
  return result;
}
export async function connectMessages(server, username, password, signal) {
  const session = { server: messageServer(server) };
  const result = await matrixRequest(session, "v3/login", { method: "POST", signal,
    body: { type: "m.login.password", identifier: { type: "m.id.user", user: username.trim() },
      password, initial_device_display_name: "Relay Web" } });
  return { ...session, user_id: result.user_id, access_token: result.access_token };
}
export const segment = encodeURIComponent;
export function roomInfo(id, data, self, previous = {}) {
  const state = [...(data.state?.events || []), ...(data.timeline?.events || [])];
  const members = { ...previous.members };
  let name = previous.name, network = previous.network || "Matrix", encrypted = !!previous.encrypted;
  for (const event of state) {
    if (event.type === "m.room.name") name = event.content?.name;
    if (event.type === "m.room.encryption") encrypted = true;
    if (event.type === "m.room.member") members[event.state_key] = event.content?.displayname || event.state_key;
    if (["m.bridge", "uk.half-shot.bridge"].includes(event.type))
      network = event.content?.protocol?.displayname || event.content?.protocol?.id || network;
  }
  name ||= Object.entries(members).filter(([key]) => key !== self).map(([, value]) => value).slice(0, 3).join(", ") || "Unnamed chat";
  return { ...previous, id, name, network, encrypted, members };
}
export function mergeEvents(old = [], incoming = []) {
  const map = new Map(old.map(e => [e.event_id, e]));
  for (const event of incoming) if (event.event_id) {
    const previous = map.get(event.event_id);
    // A redacted event must not be restored by a later history page.
    if (!previous?.unsigned?.redacted_because) map.set(event.event_id, event);
  }
  const redacted = new Set([...map.values()].filter(e => e.type === "m.room.redaction")
    .map(e => e.redacts || e.content?.redacts));
  for (const id of redacted) {
    const event = map.get(id);
    if (event) map.set(id, { ...event, content: {}, unsigned: { ...event.unsigned, redacted_because: true } });
  }
  return [...map.values()].sort((a, b) => a.origin_server_ts - b.origin_server_ts).slice(-1000);
}
export function visibleMessages(events = []) {
  const edits = new Map();
  for (const event of events) {
    const relation = event.content?.["m.relates_to"];
    if (relation?.rel_type === "m.replace") {
      const original = events.find(e => e.event_id === relation.event_id);
      if (original?.sender === event.sender && !original.unsigned?.redacted_because && !event.unsigned?.redacted_because)
        edits.set(original.event_id, event.content["m.new_content"]);
    }
  }
  return events.filter(e => ["m.room.message", "m.room.encrypted"].includes(e.type) &&
    e.content?.["m.relates_to"]?.rel_type !== "m.replace").map(e => ({ ...e, content: edits.get(e.event_id) || e.content }));
}
export function mediaPath(mxc) {
  const match = /^mxc:\/\/([a-zA-Z0-9.:[\]-]+)\/([a-zA-Z0-9_-]+)$/.exec(mxc || "");
  if (!match) throw Error("This photo has an invalid media address.");
  return `v1/media/download/${segment(match[1])}/${segment(match[2])}`;
}
export async function photoBlob(session, mxc, signal) {
  const response = await fetch(`${session.server}/_matrix/client/${mediaPath(mxc)}`, {
    headers: { Authorization: `Bearer ${session.access_token}` },
    cache: "no-store", credentials: "omit", referrerPolicy: "no-referrer",
    signal: AbortSignal.any([signal, AbortSignal.timeout(35000)]),
  });
  const type = response.headers.get("content-type")?.split(";")[0];
  if (!response.ok || !["image/jpeg", "image/png", "image/webp", "image/gif", "image/avif"].includes(type))
    throw Error("This photo could not be loaded. Try again or open it in WhatsApp.");
  const limit = 20 * 1024 * 1024;
  if (Number(response.headers.get("content-length")) > limit) {
    await response.body.cancel();
    throw Error("Open photos larger than 20 MB in WhatsApp.");
  }
  const reader = response.body.getReader(), chunks = [];
  let size = 0;
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > limit) throw Error("Open photos larger than 20 MB in WhatsApp.");
      chunks.push(value);
    }
  } finally { await reader.cancel(); }
  return new Blob(chunks, { type });
}
export async function sendMessage(session, room, body, transaction, signal, allowed = () => true) {
  if (!allowed() || room.encrypted || !body.trim()) throw Error("Choose an included, unencrypted chat before sending.");
  // Recheck live encryption state; discovery may be older than the confirmation.
  const state = await matrixRequest(session, `v3/rooms/${segment(room.id)}/state`, { signal });
  if (state.some(e => e.type === "m.room.encryption")) throw Error("This room is encrypted. Open it in a Matrix client that supports encryption.");
  if (!allowed() || signal.aborted) throw Error("Chat access changed. Review the reply again.");
  return matrixRequest(session, `v3/rooms/${segment(room.id)}/send/m.room.message/${segment(transaction)}`, {
    method: "PUT", signal, body: { msgtype: "m.text", body },
  });
}
