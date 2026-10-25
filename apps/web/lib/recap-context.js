export function visibleRecaps(recaps) {
  return recaps.filter((recap) => !recap.suppressed);
}

export function contextForPerson(recaps, partyID) {
  const seen = new Set();
  return visibleRecaps(recaps).filter((r) => !r.source_changed).flatMap((r) =>
    (r.worth_keeping || []).filter((e) => e.sender_party_id === partyID && e.source_state === "ok")
      .map((e) => ({ ...e, room_name: r.room_name })),
  ).filter((e) => {
    const key = JSON.stringify([e.room_id, e.event_id, e.quote]);
    if (seen.has(key)) return false;
    seen.add(key); return true;
  }).sort((a, b) => b.ts - a.ts);
}
