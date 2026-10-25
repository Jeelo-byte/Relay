# Relay

Relay keeps the commitments that show up in your chats: who promised what, what is still open, and the message it came from. It is a shared-understanding tracker for iOS, iPadOS, macOS, and the web. An agreement here is not a legal contract and not legal advice.

On iPhone the app opens into five places, in this order: **People**, **Events**, **Recaps**, **Messages**, and **Settings**. iPad and Mac use the same destinations in a sidebar. The web client follows the same structure.

## What each place does

- **Recaps** groups a day of chats into cards you can filter by conversation and app. Optional local generation cites the source text. Sample photos open in a collage.
- **Events** is where money, borrowed things, and the week’s plans live. You create, edit, dismiss, restore, and complete agreements yourself. Recurring items wait for you to accept the next occurrence.
- **Messages** brings chosen conversations together. Search stays on the device. Suggested replies are editable. Sending asks for confirmation, checks room encryption and consent, and records an encrypted outbox. iMessage on Mac stays read-only: Relay can copy a reply, not send it.
- **People** is a contact-style directory of shared money, items, plans, and private notes. Notes are encrypted on the device and are not synced yet.
- **Settings** covers the workspace, connections, reminders, devices, and help. Due reminders stay private. Calendar drafts can be exported.

Full chat text stays on the device and the local Matrix server. Neon stores authenticated ciphertext for derived records and short source excerpts.

The visual source for this pass is the [final product design](https://www.figma.com/design/10XdD87FnyxKWFoeF0zogy/Relay). What is implemented, what was verified, and what is still open is recorded in [docs/FINAL-DESIGN.md](docs/FINAL-DESIGN.md).

## Development

- For Xcode Run on iPhone, iPad, or Mac, open **`Relay.xcodeproj`**, select the **Relay** app scheme, and choose a destination. Opening the repository folder or `Package.swift` selects a Swift package executable instead; that executable cannot be installed on iPhone and does not provide the macOS app bundle required by notifications.
- For a connected iPhone, sign in to Xcode → Settings → Apple Accounts, then use `bash scripts/run-iphone.sh DEVICE_UDID APPLE_TEAM_ID`. The script builds and signs `Relay.app`, installs it, and launches the sample workspace. Its build log is `artifacts/iphone-device-build.log`. First launch may require trusting your developer account on the phone. Personal Team profiles need periodic renewal.
- `swift build` builds the shared library and the macOS executable.
- `swift test` runs the shared Swift tests.
- `npm install && npm run normalize` rebuilds the TypeScript normalizer for JavaScriptCore.
- `npm run dev` runs the Next.js backend and web client.
- `npm test` runs the Node tests.
- `npm run build` builds the web client for production.

The backend needs `DATABASE_URL` and `PRELOGIN_HMAC_SECRET` in a local, ignored environment file. Never put database credentials in an Apple target.

## Current checkpoint

Native and web surfaces for the five destinations are in the tree, including recurrence review, reminder planning, calendar draft export, device listing, and passphrase-based device revocation. This is still a working checkpoint. Open work includes full web Matrix conversations and sending, carrying iMessage from the Mac to other devices, live photo handling, synced person notes, data-key rotation and offline unlock, and the remaining accessibility and device checks. See [implementation decisions](docs/DECISIONS.md) and the [feature checklist](docs/FEATURES.md). The original build plan is in [docs/BuildPlan-v5.txt](docs/BuildPlan-v5.txt).

## iMessage on Mac

After Full Disk Access is granted, Relay can read new text from conversations you choose in Messages. Open **Messages → Choose Chats → iMessage**. History before you enable a chat is not imported, and Relay does not send iMessages. Details and limits are in [docs/IMESSAGE.md](docs/IMESSAGE.md).

Account recovery, passphrase changes, and passphrase-confirmed account deletion are available in the native app. See [the current tracker](context/What%20works%20in%20Relay.md) for verified behavior and remaining work.
