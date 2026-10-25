# Final product design implementation

The authoritative baseline is the teammate's `26d758c`, continued on `codex/finish-relay`. The older local feature stash remains archived and has not been applied.

Visual reference: [Relay — Final Product Design · iOS, iPadOS, macOS & Web](https://www.figma.com/design/10XdD87FnyxKWFoeF0zogy/Relay). Figma session: `0c80b2f0-5aed-4990-bcba-be2a38f32463`.

The user explicitly confirmed on October 25 that the final design replaces the earlier restrictions on recaps and includes user-confirmed message sending. Other original security and infrastructure constraints still apply. Full chat messages stay on the local Matrix server and the device; Neon receives authenticated ciphertext for derived records and bounded source excerpts.

## Sketch context

The seven-page handwritten reference is `/Users/jeelp/Downloads/App flows_261024_225127 (1).pdf`. Rendered inspection copies are ignored under `artifacts/design-notes/`.

- Page 1: onboarding sets preferences and connects apps; five destinations in this order on phones: People, Events, Recaps, Messages, Settings. Recaps is central. Native back and search actions remain accessible.
- Page 2: one date can contain multiple group chats. Recap cards grow with content. Chat names and app controls filter the timeline. Date scrubbing snaps between available dates.
- Page 3: photos open a horizontal collage; approximately ten images maximum, with a full-image viewer.
- Page 4: Events combines money, borrowed items, and a weekly calendar. People, places, and message sources provide context.
- Page 5: Messages combines selected conversations across apps. Reply suggestions use conversation context and remain editable.
- Pages 6–7: a contact-style People directory opens shared money, items, plans, and private notes. The profile avatar condenses while scrolling.

These sketches are product context. They do not authorize external messages or changes to other services by the development agent.

## Implemented in this pass

- Final warm surfaces, 16-point cards, burgundy decisions, and readable dark-mode accent text.
- Events dashboard and interactive week calendar, with existing create/edit/review/complete workflows retained.
- Messages conversation list, source-linked conversation views, selected-chat local search, editable composer, explicit confirmation, persistent encrypted outbox, and idempotent Matrix transaction IDs.
- Sending checks current room encryption and consent before submitting. iMessage on Mac now submits explicitly confirmed drafts through Messages; delivery remains visible in Messages and uncertain requests are not automatically retried.
- People grid, shared agreements, and editable encrypted device-local notes. Notes are clearly marked as not yet synced.
- Day-grouped recaps, exact quoted fallback, opt-in local Gemma generation with validated citations, source-change marking, encrypted recap sync, chat/app filters, date selection, and sample photo assets exported from Figma.
- Daily/weekly/monthly/yearly recurrence with explicit review of the next occurrence; unsupported rules remain manual.
- Private due notifications and calendar draft exports.
- Web Events, Recaps, People, saved source excerpts, Settings, accessible agreement dialogs, sample workspace, responsive navigation, and lock controls.
- API device listing and fresh-passphrase device revocation, including session and lease invalidation.

## Verification recorded so far

- 40 Swift tests passed with all opt-in tests enabled, including real local Gemma extraction and recap generation, encrypted Neon agreement and recap round trips, and isolated local Matrix send/retry/encryption/consent tests.
- Six Node tests passed with a real Neon connection, including device revocation.
- macOS Xcode builds and web production builds passed.
- Three redesigned iPhone UI tests passed before recap and sending were added.
- The first expanded iPad UI run passed the photo/source flow but exposed tests addressing sidebar labels as buttons. The selectors were corrected using the exported accessibility hierarchy; the expanded run is being repeated.

## Work still tracked

This document is a progress record, not a completion claim. Remaining work includes full web Matrix conversations/sending, Mac-to-device iMessage transport/sending, final Settings and onboarding layouts, live photo/media handling, synced person notes, account recovery and credential/key rotation, field-level sync reconciliation, remaining pipeline/provider features, full accessibility and platform verification, and final demo rehearsal. Account linking and physical-device signing still require the user's setup when implementation is ready.

## Account security continuation · October 25

On `codex/account-security`, account recovery, passphrase updates, and account deletion are now implemented with live API and native integration evidence. Recovery rotates the recovery code and revokes old device identities while retaining the data key; passphrase updates retain the recovery wrap and invalidate other sessions. Sign-in is serialized with these operations. The browser's decryption schema allowlist now accepts authenticated recap records, with dedicated interoperability and tamper tests. The context tracker is the current detailed evidence record; earlier open-work lists above describe the prior checkpoint.
