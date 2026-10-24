# Local message plane

This stack belongs to the demo Mac. It is separate from Neon. Synapse stores messages locally; Neon must receive encrypted derived records only.

The Synapse port is bound to `127.0.0.1:8008`. Do not publish it directly. A physical iPhone or iPad needs a trusted HTTPS address (for example Tailscale Serve). No certificate checks are disabled in Relay.

Runtime configurations, bridge registration tokens, signing keys, message data and account credentials live under the ignored `private/` directory. Do not commit it.

Initialization and account linking are in progress. Bridge accounts require the owner's participation. No bridge is considered connected until a real message has arrived and is visible in Relay.
