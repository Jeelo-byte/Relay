# Local message plane

This stack belongs to the local Mac. It is separate from Neon. Synapse stores messages locally; Neon must receive encrypted derived records only.

The Synapse port is bound to `127.0.0.1:8008`. Do not publish it directly. A physical iPhone or iPad needs a trusted HTTPS address (for example Tailscale Serve). No certificate checks are disabled in Relay.

Runtime configurations, bridge registration tokens, signing keys, message data and account credentials live under the ignored `private/` directory. Do not commit it.

Initialization and account linking are in progress. Bridge accounts require the owner's participation. No bridge is considered connected until a real message has arrived and is visible in Relay.

## Existing Mac commands

Start Docker Desktop, then run `npm run messages:status` or `npm run messages:start` from the repository root. These use `compose.yml` and the selected Docker context, reusing existing private configuration. The optional PostgreSQL `compose.live.yml` is separate and requires its own initialization; select it explicitly with `RELAY_MATRIX_STACK=live`.

For website sync, browser live chats, pairing, service checks, and a new host, see [the setup guide](../../docs/WEB-SETUP.md). Docker forwarding and encrypted agreement sync are separate connections.
