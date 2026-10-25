"use client";
import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { SourceMessages } from "./WorkspacePanels";
import { initials } from "./EventsWorkspace";
import { connectMessages, matrixRequest, roomInfo, mergeEvents, visibleMessages, photoBlob, sendMessage, segment } from "../lib/matrix";

function Photo({ session, content }) {
  const [url, setURL] = useState(""), [error, setError] = useState(""), [attempt, retry] = useState(0);
  useEffect(() => {
    const controller = new AbortController();
    let objectURL;
    setURL(""); setError("");
    photoBlob(session, content.url, controller.signal).then(blob => {
      if (!controller.signal.aborted) { objectURL = URL.createObjectURL(blob); setURL(objectURL); }
    }).catch(error => { if (!controller.signal.aborted) setError(error.message); });
    return () => { controller.abort(); if (objectURL) URL.revokeObjectURL(objectURL); };
  }, [session, content.url, attempt]);
  return url ? <img className="chat-photo" src={url} alt={content.body || "Received photo"} /> :
    error ? <div><p>{error}</p><button onClick={() => retry(n => n + 1)}>Retry Photo</button></div> : <p role="status">Loading photo…</p>;
}

export default function LiveMessages({ items }) {
  const [mode, setMode] = useState("live"), [session, setSession] = useState(null);
  const [server, setServer] = useState("http://127.0.0.1:8008"), [username, setUsername] = useState(""), [password, setPassword] = useState("");
  const [rooms, setRooms] = useState([]), [chosen, setChosen] = useState([]), [selected, setSelected] = useState(null);
  const [events, setEvents] = useState({}), [query, setQuery] = useState(""), [status, setStatus] = useState("Not connected");
  const [error, setError] = useState(""), [busy, setBusy] = useState(false), [draft, setDraft] = useState(""), [pending, setPending] = useState(null);
  const [sending, setSending] = useState(false), [revision, refresh] = useState(0), [historyBusy, setHistoryBusy] = useState(false);
  const active = useRef(null), generation = useRef(0), choices = useRef([]), cursors = useRef({}), sendController = useRef(null), loginController = useRef(null);
  const review = useRef(null), sendLock = useRef(false);
  const room = rooms.find(r => r.id === selected), included = chosen.includes(selected);

  function disconnect() {
    generation.current++; loginController.current?.abort(); sendController.current?.abort();
    const old = active.current; active.current = null; choices.current = []; cursors.current = {};
    setSession(null); setRooms([]); setChosen([]); setEvents({}); setSelected(null); setPending(null); setDraft(""); setPassword("");
    setBusy(false); setSending(false); setError(""); setStatus("Not connected");
    if (old) matrixRequest(old, "v3/logout", { method: "POST", body: {} }).catch(() => {});
  }
  useEffect(() => () => {
    generation.current++; loginController.current?.abort(); sendController.current?.abort();
    if (active.current) matrixRequest(active.current, "v3/logout", { method: "POST", body: {} }).catch(() => {});
    active.current = null;
  }, []);
  useEffect(() => {
    if (pending && !review.current?.open) review.current?.showModal();
    if (!pending && review.current?.open) review.current.close();
  }, [pending]);
  async function connect(event) {
    event.preventDefault(); setBusy(true); setError("");
    const current = generation.current, controller = new AbortController();
    loginController.current = controller;
    try {
      const result = await connectMessages(server, username, password, controller.signal);
      if (current !== generation.current) { matrixRequest(result, "v3/logout", { method: "POST", body: {} }).catch(() => {}); return; }
      active.current = result; setSession(result); setPassword(""); setStatus("Finding chats…");
    } catch (error) { if (current === generation.current) setError(error.message); }
    finally { if (current === generation.current) setBusy(false); }
  }
  useEffect(() => {
    if (!session) return;
    const controller = new AbortController();
    let timer, running = false, since, lastDiscovery = 0, retryMs = 3000;
    async function poll() {
      if (running || controller.signal.aborted) return;
      running = true;
      try {
        if (Date.now() - lastDiscovery > 30000) {
          const filter = { room: { timeline: { limit: 0 }, state: { types: ["m.room.name", "m.room.member", "m.room.encryption", "m.bridge", "uk.half-shot.bridge"] } } };
          const result = await matrixRequest(session, "v3/sync?timeout=0&filter=" + segment(JSON.stringify(filter)), { signal: controller.signal });
          if (controller.signal.aborted) return;
          const joined = result.rooms?.join || {};
          setRooms(old => Object.entries(joined).map(([id, data]) => roomInfo(id, data, session.user_id, old.find(r => r.id === id))).sort((a, b) => a.name.localeCompare(b.name)));
          lastDiscovery = Date.now();
        }
        if (chosen.length) {
          const filter = { room: { rooms: chosen, timeline: { limit: 100 }, state: { types: ["m.room.member", "m.room.encryption", "m.room.name", "m.bridge", "uk.half-shot.bridge"] } } };
          const result = await matrixRequest(session, `v3/sync?timeout=0&filter=${segment(JSON.stringify(filter))}${since ? "&since=" + segment(since) : ""}`, { signal: controller.signal });
          if (controller.signal.aborted) return;
          const joined = Object.entries(result.rooms?.join || {}).filter(([id]) => choices.current.includes(id));
          const left = Object.keys(result.rooms?.leave || {});
          if (left.length) {
            choices.current = choices.current.filter(id => !left.includes(id));
            setChosen(choices.current); setRooms(old => old.filter(r => !left.includes(r.id)));
          }
          setRooms(old => old.map(r => joined.some(([id]) => id === r.id) ? roomInfo(r.id, joined.find(([id]) => id === r.id)[1], session.user_id, r) : r));
          setEvents(old => {
            const next = { ...old };
            for (const id of left) delete next[id];
            for (const [id, data] of joined) {
              const timeline = data.timeline;
              next[id] = mergeEvents(old[id], timeline?.events);
              if (timeline?.prev_batch && (!cursors.current[id] || timeline.limited)) cursors.current[id] = timeline.prev_batch;
            }
            return next;
          });
          since = result.next_batch;
        }
        setError(""); setStatus(chosen.length ? "Live · checks every 3 seconds" : "Connected · choose chats to include"); retryMs = 3000;
      } catch (error) {
        if (controller.signal.aborted) return;
        setError(error.message); setStatus(error.status === 401 ? "Session expired · reconnect" : "Connection interrupted · retrying");
        retryMs = Math.min(60000, Math.max(error.retryAfter || 0, retryMs * 2));
        if (error.status === 401) { controller.abort(); return; }
      } finally {
        running = false;
        if (!controller.signal.aborted) timer = setTimeout(poll, retryMs);
      }
    }
    const wake = () => { if (!running) { clearTimeout(timer); poll(); } };
    poll(); window.addEventListener("online", wake); window.addEventListener("focus", wake);
    return () => { controller.abort(); clearTimeout(timer); window.removeEventListener("online", wake); window.removeEventListener("focus", wake); };
  }, [session, chosen, revision]);

  function choose(id, on) {
    sendController.current?.abort(); setPending(null);
    const next = on ? [...choices.current, id] : choices.current.filter(value => value !== id);
    choices.current = next; setChosen(next);
    if (!on) { delete cursors.current[id]; setEvents(old => { const next = { ...old }; delete next[id]; return next; }); }
  }
  async function older() {
    const cursor = cursors.current[selected], id = selected, current = generation.current;
    if (!cursor || !included || !session || historyBusy) return;
    setHistoryBusy(true); setError("");
    try {
      const result = await matrixRequest(session, `v3/rooms/${segment(id)}/messages?dir=b&limit=50&from=${segment(cursor)}`);
      if (current !== generation.current || !choices.current.includes(id)) return;
      cursors.current[id] = result.chunk?.length && result.end !== cursor ? result.end : null;
      setEvents(old => ({ ...old, [id]: mergeEvents(old[id], result.chunk) }));
    } catch (error) { if (current === generation.current) setError(error.message); }
    finally { if (current === generation.current) setHistoryBusy(false); }
  }
  async function confirmSend() {
    if (!pending || sendLock.current) return;
    const reply = pending, target = rooms.find(r => r.id === reply.room), current = generation.current;
    const controller = new AbortController(); sendController.current = controller;
    sendLock.current = true; setSending(true); setError("");
    try {
      const result = await sendMessage(session, target, reply.body, reply.transaction, controller.signal,
        () => current === generation.current && choices.current.includes(reply.room));
      if (current !== generation.current || controller.signal.aborted) return;
      setEvents(old => ({ ...old, [reply.room]: mergeEvents(old[reply.room], [{ event_id: result.event_id, sender: session.user_id, origin_server_ts: Date.now(), type: "m.room.message", content: { msgtype: "m.text", body: reply.body } }]) }));
      setDraft(""); setPending(null); refresh(n => n + 1);
    } catch (error) { if (current === generation.current && !controller.signal.aborted) setError(error.message + " Retry uses the same message ID to avoid duplicates."); }
    finally { sendLock.current = false; if (current === generation.current) setSending(false); }
  }
  const shown = visibleMessages(events[selected]).filter(event => !query || room?.name.toLowerCase().includes(query.toLowerCase()) ||
    `${event.content?.body || ""} ${room?.members[event.sender] || event.sender}`.toLowerCase().includes(query.toLowerCase()));
  return <section className="live-messages">
    <div className="message-tabs"><button aria-pressed={mode === "live"} onClick={() => setMode("live")}>Live Chats</button><button aria-pressed={mode === "saved"} onClick={() => setMode("saved")}>Saved Sources</button></div>
    <div hidden={mode !== "saved"}><SourceMessages items={items} /></div>
    <div hidden={mode !== "live"}>
      {!session ? <div className="message-connect quiet-card"><h2>Connect your conversations</h2><p>Connect to the same message server used by Relay on your Mac. Your Relay handle and your message-server login are separate.</p><form onSubmit={connect}>
        <label>Message server<input type="url" required value={server} onChange={e => setServer(e.target.value)} /></label>
        <label>Matrix username<input required autoComplete="username" placeholder="@relay:relay.local" value={username} onChange={e => setUsername(e.target.value)} /></label>
        <label>Matrix password<input type="password" required autoComplete="current-password" value={password} onChange={e => setPassword(e.target.value)} /></label>
        <button className="primary" disabled={busy}>{busy ? "Connecting…" : "Connect Messages"}</button>
      </form><p className="muted">Choose chats after connecting. Messages and credentials stay in memory until you lock or reload. The bridge host stores the original chats.</p><Link href="/docs#docker">Docker & Message Forwarding Setup</Link></div> : <>
        <div className="message-connection"><span role="status">{status}</span><span><button onClick={() => refresh(n => n + 1)}>Refresh Chats</button> <button onClick={disconnect}>Disconnect Messages</button></span></div>
        <div className="split-workspace live-chat-workspace"><section className="conversation-directory"><input aria-label="Search live chats and messages" placeholder="Search chats and loaded messages" value={query} onChange={e => setQuery(e.target.value)} /><p className="muted">Include only the chats you want. Choices apply to this browser session.</p>
          {rooms.filter(r => !query || r.name.toLowerCase().includes(query.toLowerCase()) || visibleMessages(events[r.id]).some(e => e.content?.body?.toLowerCase().includes(query.toLowerCase()))).map(r => <div className="live-room" key={r.id}>
            <button className="conversation-row" aria-pressed={selected === r.id} onClick={() => { setSelected(r.id); setDraft(""); setPending(null); }}><span className="avatar">{initials(r.name)}</span><span><strong>{r.name}</strong><small>{r.network}{r.encrypted ? " · Encrypted room" : ""}</small></span></button>
            <label className="include-chat"><input type="checkbox" aria-label={`Include ${r.name}`} checked={chosen.includes(r.id)} disabled={r.encrypted} onChange={e => choose(r.id, e.target.checked)} />Include</label>
          </div>)}
          {!rooms.length && <p className="empty">No joined chats found. Link WhatsApp in the bridge, then choose Refresh Chats. Accept room invitations in your Matrix client.</p>}
        </section><section className="profile-panel chat-panel">{room ? <><div className="section-heading"><h2>{room.name}</h2><span className="source-badge">{room.network}</span></div>
          {!included || room.encrypted ? <p className="empty">{room.encrypted ? "This room uses Matrix encryption. Open it in a client that supports encryption." : "Turn on Include for this chat to load its messages."}</p> : <>
            <div className="chat-history">{cursors.current[selected] && <button onClick={older} disabled={historyBusy}>{historyBusy ? "Loading…" : "Load Earlier Messages"}</button>}
              {shown.map(event => <article className={`message-bubble ${event.sender === session.user_id ? "own-message" : ""}`} key={event.event_id}><b>{room.members[event.sender] || event.sender}</b>
                {event.unsigned?.redacted_because ? <p>Message removed</p> : event.type === "m.room.encrypted" ? <p>Encrypted message · open in your Matrix client</p> : event.content?.msgtype === "m.image" && event.content.url ? <Photo session={session} content={event.content} /> : <p>{event.content?.body || "Unsupported attachment"}</p>}
                <small>{new Date(event.origin_server_ts).toLocaleString()}</small></article>)}
              {!shown.length && <p className="empty">{query ? "No loaded messages match your search." : "Waiting for messages. New messages appear automatically."}</p>}
            </div>
            <form className="reply-composer" onSubmit={e => { e.preventDefault(); if (draft.trim()) setPending({ room: room.id, name: room.name, body: draft.trim(), transaction: crypto.randomUUID() }); }}><label>Reply to {room.name}<textarea maxLength={10000} value={draft} onChange={e => setDraft(e.target.value)} placeholder="Write a reply…" /></label><button className="primary" disabled={!draft.trim() || sending}>Review Reply</button><small>Every reply needs your confirmation before it is sent.</small></form>
          </>}
        </> : <div className="empty"><h2>Your conversations, together.</h2><p>Select a chat and turn on Include to read it here.</p></div>}</section></div>
      </>}
    </div>
    {error && <p className="error" role="alert">{error}</p>}
    <dialog className="reply-review" ref={review} onCancel={e => { if (sending) e.preventDefault(); else setPending(null); }} onClose={() => { if (!sending) setPending(null); }}><h2>Send this reply?</h2><p>To {pending?.name}</p><blockquote>{pending?.body}</blockquote>{error && <p className="error" role="alert">{error}</p>}<div className="message-tabs"><button disabled={sending} onClick={() => setPending(null)}>Keep Editing</button><button className="primary" disabled={sending} onClick={confirmSend}>{sending ? "Sending…" : "Confirm Send"}</button></div></dialog>
  </section>;
}
