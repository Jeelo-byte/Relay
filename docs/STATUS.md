# Relay integration status

Updated October 25, 2026. The current detailed tracker is [What works in Relay](../context/What%20works%20in%20Relay.md). It separates passing evidence from implemented but unverified work.

Current continuation: `codex/account-security`, based on `main` at `1cede3a`. The final visual design implementation is included in baseline `5125b33`.

Verified in the latest continuation:

- 41 Swift tests passed with all live opt-ins enabled: local Gemma extraction/recaps, encrypted Neon agreement/recap round trips, recovery, deletion, and isolated Matrix sending.
- Eight Node tests passed with the live Neon contract enabled, including credential rotation, recovery invalidation, deletion, and browser agreement/recap authenticated decryption.
- Five XCUITest flows passed together on iPhone and iPad: manual creation, review/completion/persistence, chat search/source jump, recap photos/sources, and confirmation before sample sending.
- Web production build passed. The Neon audit found no seeded plaintext markers in 19 blob rows.
- Synapse and Element are healthy. Seven local bridge containers are running; this does not establish account linking or real third-party traffic.

Still open: dedicated security UI flows, physical-device signing, live account linking and cross-device demo rehearsal, complete web Matrix conversations/sending, iMessage transport/sending, real media handling, synced person notes, actual data-key rotation, offline unlock, field-level sync merging, and the remaining model/provider/accessibility work. See the context tracker for limitations and test artifact names.
