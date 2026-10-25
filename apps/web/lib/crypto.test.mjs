import test from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { sealBlob, openBlob } from "./crypto.js";

test("browser decrypts agreement and recap records with authenticated identity", async () => {
  const account = randomUUID(), dek = crypto.getRandomValues(new Uint8Array(32));
  for (const schema of ["relay.agreement/1", "relay.recap/1"]) {
    const record = { id: randomUUID(), schema, title: "Encrypted interoperability fixture", evidence: [] };
    const envelope = await sealBlob(record, dek, account, 3);
    const blob = { row_id: record.id, envelope, version: 3, key_version: 1 };
    assert.deepEqual(await openBlob(blob, dek, account), record);
    await assert.rejects(() => openBlob({ ...blob, version: 2 }, dek, account));
    await assert.rejects(() => openBlob({ ...blob, row_id: randomUUID() }, dek, account));
    await assert.rejects(() => openBlob(blob, dek, randomUUID()));
  }
});

test("browser rejects unsupported record schemas even with a valid envelope", async () => {
  const account = randomUUID(), dek = new Uint8Array(32), id = randomUUID();
  const envelope = await sealBlob({ id, schema: "relay.unknown/1" }, dek, account, 1);
  await assert.rejects(() => openBlob({ row_id: id, envelope, version: 1, key_version: 1 }, dek, account), /Unsupported record/);
});
