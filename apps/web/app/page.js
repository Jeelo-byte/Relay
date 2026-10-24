"use client";
import { useState, useEffect, useRef } from "react";
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
const date = (d) =>
  d?.date
    ? new Date(d.date + "T12:00:00").toLocaleDateString(undefined, {
        weekday: "short",
        month: "short",
        day: "numeric",
      })
    : "Not stated";
export default function Relay() {
  const [session, setSession] = useState(null),
    [handle, setHandle] = useState(""),
    [pass, setPass] = useState(""),
    [items, setItems] = useState([]),
    [selected, setSelected] = useState(null),
    [busy, setBusy] = useState(false),
    [error, setError] = useState(""),
    [query, setQuery] = useState(""),
    [filter, setFilter] = useState("All"),
    [status, setStatus] = useState("Locked");
  const versions = useRef(new Map()),
    since = useRef(0),
    pulling = useRef(false);
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
    const obj = r.status === 204 ? {} : await r.json();
    if (!r.ok)
      throw Error(
        obj.error?.message ||
          (r.status === 409
            ? "Changed on another device. Refresh and try again."
            : "Connection failed."),
      );
    return obj;
  }
  async function login(e) {
    e.preventDefault();
    setBusy(true);
    setError("");
    try {
      const h = handle.toLowerCase();
      if (!/^[a-z0-9_]{3,32}$/.test(h))
        throw Error("Use your Relay account handle.");
      const pre = await api("prelogin?handle=" + h),
        keys = await derive(pass, from64(pre.kdf_salt));
      const device = crypto.randomUUID();
      const result = await api("sessions", {
        handle: h,
        auth_key: to64(keys.auth),
        device: { device_id: device, priority: 1 },
      });
      const w = result.wraps.find(
        (w) => w.wrap_type === "passphrase" && w.key_version === 1,
      );
      const dek = await unwrap(
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
      setError(e.message);
    } finally {
      setBusy(false);
    }
  }
  async function pull(s = session) {
    if (!s || pulling.current) return;
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
        const changes = [];
        for (const row of result.items) {
          if (row.version <= (versions.current.get(row.row_id) || 0)) continue;
          if (row.deleted) {
            changes.push({ id: row.row_id, deleted: true });
            versions.current.set(row.row_id, row.version);
            continue;
          }
          try {
            changes.push(await openBlob(row, s.dek, s.account_id));
            versions.current.set(row.row_id, row.version);
          } catch {
            setError(
              "An encrypted record could not be verified. It was left unchanged.",
            );
          }
        }
        setItems((old) => {
          const map = new Map(old.map((a) => [a.id.toLowerCase(), a]));
          for (const a of changes) {
            if (a.deleted) map.delete(a.id);
            else map.set(a.id.toLowerCase(), a);
          }
          return [...map.values()];
        });
        since.current = result.next_since;
        more = result.has_more;
      }
      setStatus("Synced");
    } catch (e) {
      setStatus("Not Synced");
      setError(e.message);
    } finally {
      pulling.current = false;
    }
  }
  function lock() {
    if (session?.dek) session.dek.fill(0);
    setSession(null);
    setItems([]);
    setSelected(null);
    versions.current = new Map();
    since.current = 0;
    setStatus("Locked");
    setError("");
  }
  useEffect(() => {
    if (!session) return;
    const timer = setInterval(() => pull(session), 30000);
    const focus = () => pull(session);
    window.addEventListener("focus", focus);
    return () => {
      clearInterval(timer);
      window.removeEventListener("focus", focus);
    };
  }, [session]);
  async function change(a, kind) {
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
          session.dek,
          session.account_id,
          base + 1,
        );
      const result = await api(
        "blobs/" + a.id.toLowerCase(),
        { base_version: base, key_version: 1, envelope },
        "PUT",
      );
      versions.current.set(a.id.toLowerCase(), result.version);
      setItems((old) => old.map((x) => (x.id === a.id ? value : x)));
      setStatus("Synced");
    } catch (e) {
      setError(e.message);
      await pull();
    } finally {
      setBusy(false);
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
        (filter === "Suggested"
          ? a.review_state === "suggested"
          : a.lifecycle === "fulfilled"),
    );
  const active = items.find((a) => a.id === selected);
  if (!session)
    return (
      <main className="welcome">
        <div className="brand">▣ Relay</div>
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
        <div className="brand">▣ Relay</div>
        <nav>
          <strong>Agreements</strong>
        </nav>
        <div className="asideBottom">
          <p>Encrypted sync</p>
          <small>
            {session.handle} · {status}
          </small>
          <button onClick={lock}>Lock Relay</button>
        </div>
      </aside>
      <section className="list">
        <header>
          <h1>Agreements</h1>
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
      <section className="detail">
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
      </section>
    </div>
  );
}
