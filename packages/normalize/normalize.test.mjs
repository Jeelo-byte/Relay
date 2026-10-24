import test from "node:test";
import assert from "node:assert/strict";
import { transformSync } from "esbuild";
import { readFileSync } from "node:fs";
const code = transformSync(
  readFileSync(new URL("./index.ts", import.meta.url), "utf8"),
  { loader: "ts", format: "esm" },
).code;
const n = await import(
  "data:text/javascript;base64," + Buffer.from(code).toString("base64")
);
test("minor units, missing currency, and derived amounts", () => {
  assert.equal(n.parseAmount("€15,50").minor, 1550);
  assert.equal(n.parseAmount("¥1000").minor, 1000);
  assert.equal(n.parseAmount("20").currency, null);
  assert.equal(n.parseAmount("split $100 / 3"), null);
  assert.equal(n.parseAmount("1.250 KWD").minor, 1250);
});
test("date-only values and timezone anchoring", () => {
  const anchor = Date.parse("2026-10-25T02:00:00Z");
  assert.equal(
    n.resolveDate("tomorrow", anchor, "America/Chicago").date,
    "2026-10-25",
  );
  assert.equal(
    n.resolveDate("Friday", anchor, "America/Chicago").date,
    "2026-10-30",
  );
  assert.equal(n.resolveDate("2026-02-30", anchor, "America/Chicago"), null);
  assert.equal(
    n.resolveDate(
      "tomorrow",
      Date.parse("2026-11-01T05:30:00Z"),
      "America/Chicago",
    ).date,
    "2026-11-02",
  );
});
test("hallucinated quotes rejected; unsupported fields dropped", () => {
  const a = {
    op: "create",
    kind: "payment",
    lifecycle: "agreed",
    title: "Ticket",
    confidence: 0.9,
    obligations: [
      {
        obligor: "P2",
        obligee: "P1",
        what: "Pay back",
        amount_text: "$99",
        due_text: "Friday",
      },
    ],
    evidence: [{ m: "m1", quote: "I'll pay $40 Friday", supports:["amount","due"] }],
  };
  assert.deepEqual(
    n.validateExtraction({ agreements: [a] }, { m1: "I'll pay $40 Friday" }, [
      "P1",
      "P2",
    ]),
    [],
  );
  assert.equal(a.obligations[0].amount_text, undefined);
  a.evidence[0].quote = "You owe $99";
  assert.ok(
    n
      .validateExtraction({ agreements: [a] }, { m1: "I'll pay $40 Friday" }, [
        "P1",
        "P2",
      ])
      .includes("quote_not_found"),
  );
});
test("Unicode quote normalization and deterministic triage", () => {
  assert.equal(
    n.quoteValid("I’ll pay you", "Sure, I'll pay you tomorrow."),
    true,
  );
  assert.equal(n.quoteValid("$99", "I owe $40"), false);
  assert.equal(n.triage("I'll pay you back $40 by Friday").label, "promise");
  assert.equal(n.triage("how was your day?").label, "none");
});
