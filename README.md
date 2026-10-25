# Relay

A SwiftUI agreement tracker for iOS, iPadOS and macOS. Relay turns commitments into reviewable agreements with source evidence. You decide what to accept, edit, dismiss and complete.

## Development

- `swift build` builds the shared library and macOS executable.
- `swift test` runs the shared Swift tests.
- `npm install && npm run normalize` rebuilds the TypeScript normalizer for JavaScriptCore.
- `npm run dev` runs the Next.js backend and web client.
- The backend requires `DATABASE_URL` and `PRELOGIN_HMAC_SECRET` in a local, ignored environment file. Never put database credentials in an Apple target.

## Current checkpoint

The shared data model, design tokens, encrypted SQLite persistence, account key derivation, API client, and Neon development schema are implemented. Native screens and integration verification are in progress. This checkpoint is not a finished demo.

See [implementation decisions](docs/DECISIONS.md) for explicit scope and integration limits. The supplied build plan is preserved in [docs/BuildPlan-v5.txt](docs/BuildPlan-v5.txt).

Agreements are a shared-understanding view, not a legal contract or legal advice.

## iMessage on Mac

Relay can read new text from chosen Messages conversations on the Mac after Full Disk Access is granted. Open Inbox → Choose Chats → iMessage to connect. See [iMessage setup and limits](docs/IMESSAGE.md).
