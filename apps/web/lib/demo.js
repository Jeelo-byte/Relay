export function makeDemo() {
  const me = { party_id: "local:self", display_name_snapshot: "You", is_self: true, network: "other" };
  const alex = { party_id: "sample:alex", display_name_snapshot: "Alex Kim", is_self: false, network: "imessage" };
  const sam = { party_id: "sample:sam", display_name_snapshot: "Sam Rivera", is_self: false, network: "discord" };
  const day = (offset) => { const d = new Date(); d.setDate(d.getDate() + offset); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`; };
  return [
    ["Breakfast", "payment", alex, me, alex, 1800, "Breakfast was $18 each — send it whenever.", 0],
    ["Trail supplies", "payment", sam, sam, me, 3500, "I owe you $35 for the supplies.", 1],
    ["Water bottle", "item", alex, alex, me, null, "I’ve got your water bottle! I’ll bring it next time.", 1],
    ["Coffee & the trail", "meeting", alex, me, alex, null, "Coffee at 10 before the trail? I can drive.", 0],
    ["Study session", "meeting", sam, me, sam, null, "Evans Library at 2 tomorrow?", 1],
  ].map(([title, kind, other, from, to, minor, quote, offset]) => ({
    id: crypto.randomUUID(), schema: "relay.agreement/1", created_at: Date.now(), updated_at: Date.now(),
    title, kind, review_state: "accepted", lifecycle: "agreed", parties: [me, other],
    obligations: [{ id: crypto.randomUUID(), obligor_party_id: from.party_id, obligee_party_id: to.party_id, what: title, status: "open", amount: minor == null ? null : { minor, currency: "USD", exponent: 2 }, due: { type: "date", date: day(offset), tz_assumed: Intl.DateTimeFormat().resolvedOptions().timeZone, ambiguous: false }, place: kind === "meeting" ? { text: title.startsWith("Coffee") ? "Northgate" : "Evans Library" } : null }],
    evidence: [{ id: crypto.randomUUID(), network: other.network, room_id: "sample:" + other.party_id, event_id: crypto.randomUUID(), sender_party_id: other.party_id, ts: Date.now() - 3600000, quote, source_state: "ok", supports: ["what"] }],
    timeline: [{ id: crypto.randomUUID(), at: Date.now(), type: "created", actor: "user", pending: false }],
    provenance: { extractor: "manual" }, flags: {}, source_room_ids: ["sample:" + other.party_id], source_room_names: [other === alex ? "Weekend crew" : "Study circle"], user_note: "Fictional sample. No live messages or AI inference are claimed.",
  }));
}
