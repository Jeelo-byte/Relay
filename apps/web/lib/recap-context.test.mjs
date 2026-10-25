import test from "node:test";
import assert from "node:assert/strict";
import { contextForPerson, visibleRecaps } from "./recap-context.js";

test("automatic People context follows the speaker, source state, and recap suppression", () => {
  const source = { sender_party_id: "maya", room_id: "group", event_id: "one", quote: "I prefer Italian food", source_state: "ok", ts: 1 };
  const recap = { room_name: "Dinner", worth_keeping: [source, { ...source, sender_party_id: "alex", event_id: "two" }] };
  assert.equal(contextForPerson([recap, recap], "maya").length, 1);
  assert.equal(contextForPerson([recap], "someone-else").length, 0);
  assert.equal(contextForPerson([{ ...recap, source_changed: true }], "maya").length, 0);
  assert.equal(contextForPerson([{ ...recap, suppressed: true }], "maya").length, 0);
  assert.equal(contextForPerson([{ ...recap, worth_keeping: [{ ...source, source_state: "deleted" }] }], "maya").length, 0);
  assert.equal(visibleRecaps([recap, { ...recap, suppressed: true }]).length, 1);
  assert.deepEqual(contextForPerson([{ room_name: "Legacy" }], "maya"), []);
});
