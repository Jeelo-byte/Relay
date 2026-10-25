import test from "node:test";
import assert from "node:assert/strict";
import { createGateway } from "./host-gateway.mjs";

test("loopback gateway answers health and hides admin paths", async () => {
  const gateway = createGateway();
  await new Promise(resolve => gateway.listen(0, "127.0.0.1", resolve));
  const { port } = gateway.address();
  try {
    const health = await fetch(`http://127.0.0.1:${port}/healthz`);
    assert.equal(health.status, 200);
    assert.equal((await health.json()).status, "running");
    assert.equal((await fetch(`http://127.0.0.1:${port}/_synapse/admin`)).status, 404);
    assert.equal((await fetch(`http://127.0.0.1:${port}/_matrix/federation/v1/version`)).status, 404);
  } finally {
    await new Promise(resolve => gateway.close(resolve));
  }
});
