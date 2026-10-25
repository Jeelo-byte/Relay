"use client";
import { useEffect, useRef, useState } from "react";
import QRCode from "qrcode";
import jsQR from "jsqr";
import { from64, to64 } from "../lib/crypto";
import { pairingAPI as api, pairingHash, pairingCode, pairingURL, parsePairing, pairingWrap } from "../lib/pairing";
const label = priority => ({ 1: "Web browser", 2: "iPhone", 3: "iPad", 4: "Mac" })[priority] || "Device";

export function PairDevice({ session }) {
  const [invite, setInvite] = useState(null), [qr, setQR] = useState(""), [target, setTarget] = useState(null),
    [error, setError] = useState(""), [busy, setBusy] = useState(false), [message, setMessage] = useState("");
  const current = useRef(null), generation = useRef(0);
  async function cancel() {
    generation.current++;
    const old = current.current; current.current = null;
    setInvite(null); setQR(""); setTarget(null);
    if (old) { old.key.fill(0); await api("pairings/" + old.id, null, "DELETE", session.token).catch(() => {}); }
  }
  useEffect(() => () => { generation.current++; const old = current.current; current.current = null;
    if (old) { old.key.fill(0); api("pairings/" + old.id, null, "DELETE", session.token).catch(() => {}); }
  }, [session.token]);
  async function create() {
    await cancel(); const run = generation.current; setBusy(true); setError(""); setMessage("");
    const key = crypto.getRandomValues(new Uint8Array(32)), id = crypto.randomUUID();
    try {
      const encrypted = await pairingWrap(session.dek, key, session.account_id, id);
      const result = await api("pairings", { pairing_id: id, key_hash: await pairingHash(key), encrypted_dek: to64(encrypted) }, "POST", session.token);
      if (run !== generation.current) { key.fill(0); api("pairings/" + id, null, "DELETE", session.token).catch(() => {}); return; }
      const link = pairingURL(location.origin, id, key), code = await pairingCode(key);
      const image = await QRCode.toDataURL(link, { width: 288, margin: 4, errorCorrectionLevel: "M" });
      if (run !== generation.current) { key.fill(0); api("pairings/" + id, null, "DELETE", session.token).catch(() => {}); return; }
      const next = { id, key, link, code, expires: Date.parse(result.expires_at) }; current.current = next; setInvite(next); setQR(image);
    } catch (e) { key.fill(0); if (run === generation.current) setError(e.message); }
    finally { if (run === generation.current) setBusy(false); }
  }
  useEffect(() => {
    if (!invite) return;
    let stopped = false, timer;
    async function poll() {
      try {
        if (Date.now() >= invite.expires) throw Error("This code expired. Show a new code to continue.");
        const result = await api("pairings/" + invite.id, null, "GET", session.token);
        if (!stopped) setTarget(result.target_device_id ? result : null);
      } catch (e) {
        if (!stopped) {
          if (e.status === 410 && current.current?.approved) setMessage("Pairing has closed. Check your other device to continue.");
          else setError(e.message);
          await cancel();
        }
        return;
      }
      if (!stopped) timer = setTimeout(poll, 2000);
    }
    poll(); return () => { stopped = true; clearTimeout(timer); };
  }, [invite, session.token]);
  async function approve() {
    const active = current.current; if (!active || !target) return;
    setBusy(true); setError("");
    try { await api(`pairings/${active.id}/approve`, { device_id: target.target_device_id }, "POST", session.token);
      if (current.current === active) { active.approved = true; setMessage("Approved. Keep both devices open while pairing finishes."); }
    } catch (e) { setError(e.message); } finally { setBusy(false); }
  }
  return <section className="pairing-panel" aria-label="Pair a device">
    <h2>Pair a Device</h2><p>Open Relay on your other device and choose <strong>Scan Pairing Code</strong>.</p>
    {qr && <img className="pairing-qr" src={qr} width="288" height="288" alt="Private Relay pairing code. Scan with your other device." />}
    {invite && <><p>Check code: <strong className="pairing-check">{invite.code}</strong></p>
      <p>Expires at {new Date(invite.expires).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" })}. Keep this code private.</p>
      {location.hostname === "localhost" || location.hostname === "127.0.0.1" ? <p role="status">For an iPhone, open Relay using your Mac’s reachable HTTPS address before showing this code.</p> : null}
      {target && <div role="status"><p><strong>{label(target.target_priority)}</strong> wants to pair. Compare the check code on both devices.</p>
        <p>This gives the device access to your encrypted agreements and recaps.</p>
        <button className="primary" onClick={approve} disabled={busy || invite.approved}>Approve {label(target.target_priority)}</button></div>}
      <details><summary>Can’t scan?</summary><p>Paste this private link into Relay on your other device.</p><input aria-label="Private pairing link" readOnly value={invite.link} onFocus={e => e.target.select()} /></details>
      <button onClick={cancel}>Cancel Pairing</button></>}
    {!invite && <button className="primary" onClick={create} disabled={busy}>{busy ? "Creating Code…" : "Show Pairing Code"}</button>}
    {message && <p role="status">{message}</p>}{error && <p role="alert" className="error">{error}</p>}
  </section>;
}

export function JoinDevice({ onPaired }) {
  const [text, setText] = useState(""), [pending, setPending] = useState(null), [code, setCode] = useState(""),
    [error, setError] = useState(""), [busy, setBusy] = useState(false), [camera, setCamera] = useState(false);
  const video = useRef(null), current = useRef(null), generation = useRef(0), joining = useRef(false);
  async function cancel() {
    generation.current++; const old = current.current; current.current = null;
    setPending(null); setCode(""); setText(""); setBusy(false);
    if (old) { old.key.fill(0); api(`pairings/${old.id}/cancel`, { poll_key: old.poll }).catch(() => {}); }
  }
  useEffect(() => {
    const fragment = location.hash;
    if (fragment.startsWith("#pair=")) { const link = location.href; history.replaceState(null, "", location.pathname + location.search); setText(link); }
    return () => { generation.current++; const old = current.current; current.current = null;
      if (old) { old.key.fill(0); api(`pairings/${old.id}/cancel`, { poll_key: old.poll }).catch(() => {}); }
    };
  }, []);
  async function join(link = text) {
    if (joining.current) return; joining.current = true;
    await cancel(); const run = generation.current; setBusy(true); setError(""); setCamera(false);
    let parsed, poll;
    try {
      parsed = parsePairing(link, location.origin);
      poll = to64(crypto.getRandomValues(new Uint8Array(32)));
      const device = crypto.randomUUID();
      const result = await api(`pairings/${parsed.id}/join`, { key_hash: await pairingHash(parsed.key),
        poll_hash: await pairingHash(from64(poll)), device: { device_id: device, priority: 1 } });
      if (run !== generation.current) { parsed.key.fill(0); api(`pairings/${parsed.id}/cancel`, { poll_key: poll }).catch(() => {}); return; }
      const next = { ...parsed, poll, device, expires: Date.parse(result.expires_at) };
      current.current = next; setPending(next); setCode(await pairingCode(parsed.key)); setText("");
    } catch (e) { parsed?.key.fill(0); if (run === generation.current) setError(e.message); }
    finally { joining.current = false; if (run === generation.current) setBusy(false); }
  }
  useEffect(() => {
    if (!pending) return; let stopped = false, timer;
    async function poll() {
      let result;
      try {
        if (Date.now() >= pending.expires) throw Error("Pairing expired. Show a new code on your other device.");
        result = await api(`pairings/${pending.id}/claim`, { poll_key: pending.poll });
        if (stopped) { if (result.token) api("sessions/current", null, "DELETE", result.token).catch(() => {}); return; }
        if (result.state === "paired") {
          const dek = await pairingWrap(from64(result.encrypted_dek), pending.key, result.account_id, pending.id, true);
          if (stopped) { dek.fill(0); api("sessions/current", null, "DELETE", result.token).catch(() => {}); return; }
          current.current = null; pending.key.fill(0);
          onPaired({ token: result.token, account_id: result.account_id, handle: result.handle, dek }); return;
        }
      } catch (e) {
        if (result?.token) api("sessions/current", null, "DELETE", result.token).catch(() => {});
        if (!stopped) { setError(e.message); await cancel(); } return;
      }
      if (!stopped) timer = setTimeout(poll, 2000);
    }
    poll(); return () => { stopped = true; clearTimeout(timer); };
  }, [pending]);
  useEffect(() => {
    if (!camera) return; let stopped = false, stream, frame;
    const canvas = document.createElement("canvas"), context = canvas.getContext("2d", { willReadFrequently: true });
    const scan = () => {
      if (stopped) return;
      const v = video.current;
      if (v?.readyState >= 2) {
        canvas.width = 640; canvas.height = Math.round(640 * v.videoHeight / v.videoWidth);
        context.drawImage(v, 0, 0, canvas.width, canvas.height);
        const pixels = context.getImageData(0, 0, canvas.width, canvas.height), found = jsQR(pixels.data, pixels.width, pixels.height);
        if (found) { join(found.data); return; }
      }
      frame = requestAnimationFrame(scan);
    };
    navigator.mediaDevices?.getUserMedia({ video: { facingMode: "environment" }, audio: false }).then(async s => {
      stream = s; if (stopped) { s.getTracks().forEach(t => t.stop()); return; }
      video.current.srcObject = s; await video.current.play(); scan();
    }).catch(() => { if (!stopped) { setCamera(false); setError("Camera unavailable. Allow camera access, or paste your private pairing link below."); } });
    if (!navigator.mediaDevices?.getUserMedia) { setCamera(false); setError("Use HTTPS to scan, or paste your pairing link below."); }
    return () => { stopped = true; cancelAnimationFrame(frame); stream?.getTracks().forEach(t => t.stop()); };
  }, [camera]);
  return <section className="pairing-panel" aria-label="Connect this device">
    <h2>Pair This Device</h2><p>On your signed-in Mac, iPhone, or browser, open <strong>Settings → Devices → Pair a Device</strong>. Scan its code here.</p>
    {pending ? <><p role="status">Waiting for approval on your other device.</p><p>Check code: <strong className="pairing-check">{code}</strong></p><p>Compare this code, then approve <strong>Web browser</strong> on your other device.</p><button onClick={cancel}>Cancel Pairing</button></> : <>
      {camera ? <><video ref={video} className="pairing-camera" muted playsInline aria-label="Pairing code camera" /><button onClick={() => setCamera(false)}>Stop Camera</button></> : <button className="primary" onClick={() => { setError(""); setCamera(true); }} disabled={busy}>Scan Pairing Code</button>}
      <form onSubmit={e => { e.preventDefault(); join(); }}><label>Or paste a private pairing link<input type="text" value={text} onChange={e => setText(e.target.value)} autoComplete="off" spellCheck="false" /></label><button disabled={busy || !text.trim()}>{busy ? "Connecting…" : "Connect with Link"}</button></form>
      <p>New to Relay? Create your first account in the native app.</p></>}
    {error && <p role="alert" className="error">{error}</p>}
  </section>;
}
