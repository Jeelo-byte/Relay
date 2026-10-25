"use client";
import { useState, useEffect, useRef } from "react";
import Link from "next/link";
import EventsWorkspace, { Icon, formatDue, initials } from "./EventsWorkspace";
import { PeopleWorkspace, WebSettings } from "./WorkspacePanels";
import RecapsWorkspace from "./RecapsWorkspace";
import LiveMessages from "./LiveMessages";
import {
  derive,
  unwrap,
  from64,
  to64,
  openBlob,
  sealBlob,
} from "../lib/crypto";
const money = (m) =>
  m
    ? new Intl.NumberFormat(undefined, {
        style: "currency",
        currency: m.currency,
      }).format(m.minor / 10 ** m.exponent)
    : "Not stated";
const date = formatDue;
export default function Relay() {
  const [session, setSession] = useState(null),
    [handle, setHandle] = useState(""),
    [pass, setPass] = useState(""),
    [items, setItems] = useState([]),
    [recaps, setRecaps] = useState([]),
    [selected, setSelected] = useState(null),
    [busy, setBusy] = useState(false),
    [error, setError] = useState(""),
    [query, setQuery] = useState(""),
    [filter, setFilter] = useState("All"),
    [status, setStatus] = useState("Locked"),
    [destination, setDestination] = useState("Recaps"),
    [browse, setBrowse] = useState(false);
  const versions = useRef(new Map()),
    since = useRef(0),
    pulling = useRef(false),
    epoch = useRef(0),
    detailDialog = useRef(null);
  async function api(
    path,
    body,
    method = body ? "POST" : "GET",
    token = session?.token,
  ) {
    const r = await fetch("/api/v1/" + path, {
      method,
      headers: {
        "Content-Type": "application/json",
        ...(token ? { Authorization: "Bearer " + token } : {}),
      },
      ...(body ? { body: JSON.stringify(body) } : {}),
    });
    const obj = r.status === 204 ? {} : await r.json().catch(() => ({ error: { message: "The Relay server returned an invalid response. Check that the web server is running." } }));
    if (!r.ok) {
      const error = Error(obj.error?.message || (r.status === 409
        ? "Changed on another device. Refresh and try again." : "Connection failed."));
      error.status = r.status;
      throw error;
    }
    return obj;
  }
  async function login(e) {
    e.preventDefault();
    setBusy(true);
    setError("");
    let keys, result, dek;
    try {
      if (!globalThis.isSecureContext || !crypto.subtle)
        throw Error("Open Relay on localhost or through HTTPS to unlock encrypted sync.");
      const h = handle.trim().toLowerCase();
      if (!/^[a-z0-9_]{3,32}$/.test(h))
        throw Error("Use your Relay account handle.");
      const pre = await api("prelogin?handle=" + h);
      keys = await derive(pass, from64(pre.kdf_salt));
      const device = crypto.randomUUID();
      result = await api("sessions", {
        handle: h,
        auth_key: to64(keys.auth),
        device: { device_id: device, priority: 1 },
      });
      const w = result.wraps.find(
        (w) => w.wrap_type === "passphrase" && w.key_version === 1,
      );
      if (!w) throw Error("This account’s passphrase key is unavailable.");
      dek = await unwrap(
        from64(w.wrapped_dek),
        keys.kek,
        result.account_id,
      );
      const s = { ...result, dek, handle: h };
      keys.kek.fill(0);
      keys.auth.fill(0);
      setSession(s);
      setPass("");
      await pull(s);
    } catch (e) {
      dek?.fill(0);
      if (result?.token) api("sessions/current", null, "DELETE", result.token).catch(() => {});
      setError(e.message);
    } finally {
      keys?.kek.fill(0); keys?.auth.fill(0);
      setBusy(false);
    }
  }
  async function pull(s = session) {
    if (!s || pulling.current) return;
    const generation = epoch.current;
    pulling.current = true;
    setStatus("Syncing…");
    try {
      let more = true;
      while (more) {
        const result = await api(
          "blobs?since=" + since.current + "&limit=500",
          null,
          "GET",
          s.token,
        );
        if (generation !== epoch.current) return;
        const changes = [];
        let unverified = false;
        for (const row of result.items) {
          row.row_id = row.row_id.toLowerCase();
          if (row.version <= (versions.current.get(row.row_id) || 0)) continue;
          if (row.deleted) {
            changes.push({ id: row.row_id, deleted: true });
            versions.current.set(row.row_id, row.version);
            continue;
          }
          try {
            const value = await openBlob(row, s.dek, s.account_id);
            if (generation !== epoch.current) return;
            if (row.version <= (versions.current.get(row.row_id) || 0)) continue;
            const sampleRoom = (id) => id.startsWith("!demo-") && id.endsWith(":relay.local");
            if ((value.schema === "relay.recap/1" && sampleRoom(value.room_id)) ||
              (value.source_room_ids?.length && value.source_room_ids.every(sampleRoom))) {
              versions.current.set(row.row_id, row.version); continue;
            }
            changes.push(value);
            versions.current.set(row.row_id, row.version);
          } catch { unverified = true; }
        }
        setItems((old) => {
          const map = new Map(old.map((a) => [a.id.toLowerCase(), a]));
          for (const a of changes) {
            if (a.deleted) map.delete(a.id.toLowerCase());
            else if (a.schema === "relay.agreement/1") map.set(a.id.toLowerCase(), a);
          }
          return [...map.values()];
        });
        setRecaps((old) => {
          const map = new Map(old.map((r) => [r.id.toLowerCase(), r]));
          for (const r of changes) {
            if (r.deleted) map.delete(r.id.toLowerCase());
            else if (r.schema === "relay.recap/1") map.set(r.id.toLowerCase(), r);
          }
          return [...map.values()];
        });
        if (unverified) throw Error("An encrypted record could not be verified. Sync will retry; its position has been preserved.");
        since.current = result.next_since;
        more = result.has_more;
      }
      if (generation === epoch.current) { setStatus("Synced"); setError(""); }
    } catch (e) {
      if (generation !== epoch.current) return;
      if (e.status === 401) { lock(); setError("Your session expired or this device was removed. Unlock Relay again."); return; }
      setStatus("Not Synced");
      setError(e.message);
    } finally {
      if (generation === epoch.current) pulling.current = false;
    }
  }
  function lock() {
    if (session?.token) api("sessions/current", null, "DELETE", session.token).catch(() => {});
    epoch.current += 1;
    pulling.current = false;
    setQuery("");
    setFilter("All");
    setDestination("Events");
    setBrowse(false);
    if (session?.dek) session.dek.fill(0);
    setSession(null);
    setItems([]);
    setRecaps([]);
    setSelected(null);
    versions.current = new Map();
    since.current = 0;
    setStatus("Locked");
    setBusy(false);
    setError("");
  }
  useEffect(() => {
    if (!session) return;
    const timer = setInterval(() => pull(session), 30000);
    const focus = () => pull(session);
    window.addEventListener("focus", focus);
    window.addEventListener("online", focus);
    return () => {
      clearInterval(timer);
      window.removeEventListener("focus", focus);
      window.removeEventListener("online", focus);
    };
  }, [session]);
  useEffect(() => {
    if (!session) return;
    let timeout;
    const activity = () => { clearTimeout(timeout); timeout = setTimeout(lock, 5 * 60 * 1000); };
    const pagehide = () => lock();
    const events = ["pointerdown", "keydown", "touchstart"];
    events.forEach(event => window.addEventListener(event, activity, { passive: true }));
    window.addEventListener("pagehide", pagehide);
    activity();
    return () => {
      clearTimeout(timeout);
      events.forEach(event => window.removeEventListener(event, activity));
      window.removeEventListener("pagehide", pagehide);
    };
  }, [session]);
  async function change(a, kind) {
    const currentSession = session, generation = epoch.current;
    if (!currentSession) return;
    setBusy(true);
    setError("");
    try {
      const value = structuredClone(a);
      value.updated_at = Date.now();
      if (kind === "accepted" || kind === "dismissed")
        value.review_state = kind;
      if (kind === "done") {
        value.lifecycle = "fulfilled";
        value.obligations.forEach((o) => {
          o.status = "done";
          o.done_at = Date.now();
        });
      }
      value.timeline.push({
        id: crypto.randomUUID(),
        at: Date.now(),
        type: kind === "done" ? "status_changed" : kind,
        actor: "user",
        field_path: null,
        old: null,
        new: null,
        evidence_id: null,
        pending: false,
      });
      const base = versions.current.get(a.id.toLowerCase()) || 0,
        envelope = await sealBlob(
          value,
          currentSession.dek,
          currentSession.account_id,
          base + 1,
        );
      if (generation !== epoch.current) return;
      const result = await api(
        "blobs/" + a.id.toLowerCase(),
        { base_version: base, key_version: 1, envelope },
        "PUT",
        currentSession.token,
      );
      if (generation !== epoch.current) return;
      versions.current.set(a.id.toLowerCase(), result.version);
      setItems((old) => old.map((x) => (x.id === a.id ? value : x)));
      setStatus("Synced");
    } catch (e) {
      if (generation !== epoch.current) return;
      setError(e.message);
      await pull(currentSession);
    } finally {
      if (generation === epoch.current) setBusy(false);
    }
  }
  const visible = items
    .filter(
      (a) =>
        a.review_state !== "dismissed" &&
        (
          a.title +
          " " +
          a.parties.map((p) => p.display_name_snapshot).join(" ")
        )
          .toLowerCase()
          .includes(query.toLowerCase()),
    )
    .filter(
      (a) =>
        filter === "All" ||
        (filter === "Money" && a.kind === "payment") ||
        (filter === "Items" && a.kind === "item") ||
        (filter === "Suggested"
          ? a.review_state === "suggested"
          : filter === "Done" && a.lifecycle === "fulfilled"),
    );
  const active = items.find((a) => a.id === selected);
  useEffect(() => {
    if (active && detailDialog.current && !detailDialog.current.open) detailDialog.current.showModal();
    if (!active && detailDialog.current?.open) detailDialog.current.close();
  }, [active]);
  const navigate = (name) => { setDestination(name); setSelected(null); setQuery(""); setFilter("All"); setBrowse(false); };
  const openBrowse = (nextFilter) => { setFilter(nextFilter); setBrowse(true); };
  const destinations = ["Recaps", "Events", "Messages", "People", "Settings"];
  const navigation = (mobile = false) => <nav className={mobile ? "mobile-navigation" : "primary-navigation"} aria-label={mobile ? "Mobile navigation" : "Primary navigation"}>{destinations.map((name) => <button key={name} onClick={() => navigate(name)} aria-current={destination === name ? "page" : undefined}><Icon name={name.toLowerCase()} /><span>{name}</span></button>)}</nav>;

  if (!session)
    return (
      <main className="welcome">
        <div className="brand"><Icon name="logo" /> Relay</div>
        <h1>
          Every promise.
          <br />A little clearer.
        </h1>
        <p>
          Unlock the agreements you created on your Apple devices. Your keys
          stay in this browser’s memory.
        </p>
        <form onSubmit={login}>
          <label>
            Handle
            <input
              value={handle}
              onChange={(e) => setHandle(e.target.value)}
              autoComplete="username"
              required
            />
          </label>
          <label>
            Passphrase
            <input
              type="password"
              value={pass}
              onChange={(e) => setPass(e.target.value)}
              autoComplete="current-password"
              required
            />
          </label>
          {error && (
            <p role="alert" className="error">
              {error}
            </p>
          )}
          <button className="primary" disabled={busy}>
            {busy ? "Unlocking…" : "Unlock Agreements"}
          </button>
        </form>
        <nav className="welcome-links" aria-label="Before you unlock">
          <Link className="setup-guide-link" href="/">About Relay</Link>
          <Link className="setup-guide-link" href="/docs">Set Up WhatsApp & Read the Guide</Link>
        </nav>
        <small>
          Create an account in the Relay native app first.
          <br />
          Reloading this page clears decrypted agreements.
        </small>
      </main>
    );
  return (
    <div className="shell">
      <aside>
        <div className="brand"><Icon name="logo" /> Relay</div>
        <input aria-label="Search Relay" placeholder="Search Relay" value={query} onChange={(e) => { setQuery(e.target.value); setDestination("Events"); setBrowse(true); }} />
        {navigation()}
        <div className="asideBottom"><div className="account-summary"><span className="avatar">{initials(session.handle)}</span><span><b>{session.handle}</b><small>Personal workspace</small></span></div><button onClick={lock}>Lock Relay</button></div>
      </aside>
      <main className="workspace-main">
        <header className="workspace-toolbar"><h1>{browse ? "All Agreements" : destination}</h1><span className="toolbar-actions"><span className="source-badge" role="status">{status}</span><button onClick={() => pull()} disabled={busy} aria-label="Sync agreements">↻</button><button onClick={lock} className="mobile-lock">Lock</button></span></header>
        {error && <p role="alert" className="error">{error}</p>}
        {destination === "Recaps" && <RecapsWorkspace recaps={recaps} items={items} onSelectAgreement={setSelected} onSettings={() => navigate("Settings")} />}
        {destination === "Events" && !browse && <EventsWorkspace items={visible} onSelect={setSelected} onBrowse={openBrowse} />}
        {destination === "People" && <PeopleWorkspace items={items} onSelect={setSelected} />}
        <div hidden={destination !== "Messages"}><LiveMessages items={items} /></div>
        {destination === "Settings" && <WebSettings session={session} items={items} lock={lock} />}
        {destination === "Events" && browse && <>
      <section className="list">
        <header>
          <h2>All Agreements</h2>
          <button onClick={() => pull()} aria-label="Sync agreements">
            ↻
          </button>
        </header>
        <p className="muted">Every agreement, backed by its source.</p>
        <input
          aria-label="Search agreements"
          placeholder="Search Agreements"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
        />
        <div className="filters">
          {["All", "Suggested", "Done"].map((f) => (
            <button
              aria-pressed={filter === f}
              key={f}
              onClick={() => setFilter(f)}
            >
              {f}
            </button>
          ))}
        </div>
        {error && (
          <p role="alert" className="error">
            {error}
          </p>
        )}
        {!visible.length && (
          <p className="empty">
            No agreements here yet. Create one on your Apple device, then sync.
          </p>
        )}
        {visible.map((a) => (
          <article
            key={a.id}
            className={
              (a.review_state === "suggested" ? "suggested " : "") +
              (selected === a.id ? "selected" : "")
            }
          >
            <button className="cardButton" onClick={() => setSelected(a.id)}>
              <span className="chip">
                {a.lifecycle === "fulfilled" ? "Done" : a.lifecycle}
              </span>
              <h2>{a.title}</h2>
              <p>{a.parties.find((p) => !p.is_self)?.display_name_snapshot}</p>
              <strong>
                {a.obligations[0]?.amount
                  ? money(a.obligations[0].amount)
                  : a.obligations[0]?.what}
              </strong>
              <p>{date(a.obligations[0]?.due)}</p>
              <small>
                {a.evidence.length} sources ·{" "}
                {a.provenance.extractor === "manual" ? "Manual" : "Local"}
              </small>
            </button>
            {a.review_state === "suggested" && (
              <div className="actions">
                <button
                  className="primary"
                  disabled={busy}
                  onClick={() => change(a, "accepted")}
                >
                  Accept
                </button>
                <button disabled={busy} onClick={() => change(a, "dismissed")}>
                  Dismiss
                </button>
              </div>
            )}
          </article>
        ))}
        <footer>A shared-understanding view, not a legal contract.</footer>
      </section>
        </>}
      </main>
      {navigation(true)}
      <dialog ref={detailDialog} className="detail" onCancel={() => setSelected(null)} onClose={() => setSelected(null)}>
        <button className="close-detail" onClick={() => setSelected(null)} aria-label="Close agreement">Close</button>
        {active ? (
          <>
            <span className="chip">{active.lifecycle}</span>
            <h1>{active.title}</h1>
            <div className="actions">
              {active.review_state === "suggested" ? (
                <button
                  className="primary"
                  disabled={busy}
                  onClick={() => change(active, "accepted")}
                >
                  Accept Agreement
                </button>
              ) : (
                active.lifecycle !== "fulfilled" && (
                  <button
                    className="primary"
                    disabled={busy}
                    onClick={() => change(active, "done")}
                  >
                    Mark Done
                  </button>
                )
              )}
            </div>
            <h2>The Agreement</h2>
            {active.obligations.map((o) => (
              <article key={o.id}>
                <h3>{o.what}</h3>
                <dl>
                  <dt>Amount</dt>
                  <dd>{money(o.amount)}</dd>
                  <dt>Due</dt>
                  <dd>{date(o.due)}</dd>
                  <dt>Place</dt>
                  <dd>{o.place?.text || "Not stated"}</dd>
                </dl>
              </article>
            ))}
            <h2>Source Trail</h2>
            {active.evidence.map((e) => (
              <article key={e.id}>
                <strong>
                  {active.parties.find((p) => p.party_id === e.sender_party_id)
                    ?.display_name_snapshot || "Source"}
                </strong>
                <small> · {e.network}</small>
                <blockquote>{e.quote}</blockquote>
                <small>{new Date(e.ts).toLocaleString()}</small>
              </article>
            ))}
            <h2>Timeline</h2>
            {[...active.timeline].reverse().map((e) => (
              <p key={e.id}>
                {e.type.replaceAll("_", " ")}{" "}
                <small>· {new Date(e.at).toLocaleString()}</small>
              </p>
            ))}
            <footer>
              A shared-understanding view, not a legal contract or legal advice.
            </footer>
          </>
        ) : (
          <div className="empty">
            <h1>
              Keep your word.
              <br />
              Keep the details.
            </h1>
            <p>Choose an agreement to inspect its source trail.</p>
          </div>
        )}
      </dialog>
    </div>
  );
}
