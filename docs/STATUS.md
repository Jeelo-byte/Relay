# Relay integration status

Updated October 25, 2026. The current detailed tracker is [What works in Relay](../context/What%20works%20in%20Relay.md). It separates passing evidence from implemented but unverified work.

Current checkpoint: `main` at `62f2cdc`. GitHub Actions run `40180451095` passed the web job and `swift test`. The account-security work merged as `3cceeaa`. The final visual design implementation from `5125b33` remains in that history.

Verified in the latest continuation:

- 41 Swift tests passed with all live opt-ins enabled: local Gemma extraction/recaps, encrypted Neon agreement/recap round trips, recovery, deletion, and isolated Matrix sending.
- Eight Node tests passed with the live Neon contract enabled, including credential rotation, recovery invalidation, deletion, and browser agreement/recap authenticated decryption.
- Five XCUITest flows passed together on iPhone and iPad: manual creation, review/completion/persistence, chat search/source jump, recap photos/sources, and confirmation before sample sending.
- Web production build passed. The Neon audit found no seeded plaintext markers in 19 blob rows.
- Synapse and Element are healthy. Seven local bridge containers are running; this does not establish account linking or real third-party traffic.

On `main` and not yet proven on a real device or network: Mac iMessage send, contact import, and profile linking; local website Matrix chats; WhatsApp’s four-step setup; offline unlock after an online sign-in; and localhost host scripts (`scripts/start-host.sh`, the loopback gateway, and encrypted backup). A real iMessage was not sent.

Still open: Full Disk Access and Automation before a real iMessage read or send, Tailscale HTTPS, Figma onboarding for every messaging service, data-key rotation, field-level multi-device conflict merge, dedicated security UI flows, cross-device demo rehearsal, real media handling, synced person notes, and the remaining model/provider/accessibility work. The Mac app uses the Figma desktop workspace. iMessage sending stays on the tested outbox, with the chat id and text passed as Apple event parameters. See the context tracker for limitations and test artifact names.
