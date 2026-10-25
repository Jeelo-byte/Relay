# Pair Relay devices

QR pairing is the default connection path on a new native device and on the web workspace. Create the first Relay account in the native app; existing devices can still unlock with a passphrase or recovery code.

1. On an unlocked device, open **Settings → Devices → Pair a Device** and choose **Show Pairing Code**.
2. On the new iPhone, iPad, Mac, or web workspace, choose **Scan Pairing Code**. Allow camera access when asked. A private pairing link is available as an accessible fallback.
3. In the native app, review the server address and choose **Pair This Device**. In the browser, scan the code or paste the link and choose **Connect with Link**. A link opened from the system camera is read from the URL fragment and removed from the address bar; it still requires the connection action.
4. Compare the check code on both devices. Approve the requesting device on the original device. Keep both open until the new device unlocks.

The QR includes the account server address, so it does not need to be entered again. The server must already be reachable from the new device over trusted HTTPS. A localhost code only reaches services on the same machine. Pairing does not create a network route or install/start the Mac host. See [hosting](HOSTING.md).

## Boundaries

Pairing grants a new device a Relay session and access to the account's encrypted workspace. It does not transfer Matrix credentials, WhatsApp linked-device sessions, chat inclusion choices, contacts, private person notes, or Mac iMessage history. Integration onboarding remains a separate flow. The new device appears in the existing Devices list and can be revoked there.

Native paired sessions use the existing local Keychain and biometric unlock. They do not acquire a passphrase-derived offline-unlock wrap; passphrase offline unlock becomes available after signing in online with the passphrase on that device. Browser sessions remain in memory and end on lock/reload.

## Protocol and deployment

Apply the additive `002_pairing.sql` migration with `node --env-file=apps/web/.env.local scripts/migrate.mjs`. The runner applies the repository's idempotent migrations in order using the direct database endpoint. Existing account and workspace records are preserved.

- An authenticated device generates a random 256-bit QR secret and invitation UUID locally. It wraps the workspace DEK with AES-256-GCM, binding the account and invitation ID in the authenticated data.
- The server stores the secret's SHA-256 hash, the encrypted DEK, the creating session, and the account credential verifier. The raw QR secret stays in the link fragment and on the two devices; it is not sent to the API.
- The scanning device generates a separate 256-bit redemption secret and fresh device UUID. Joining reserves the invitation for this device. Only the redemption hash reaches the join API; the raw redemption secret is never included in the QR.
- The original session reviews the requesting device type and explicitly approves its UUID. No session or workspace key is released before approval.
- Claim atomically consumes the invitation, registers the device, and issues its session. The scanning client decrypts the DEK locally. Competing claims yield at most one session.
- Invitations expire after five minutes. Cancellation, creating-session logout/revocation/expiry, account deletion, and credential changes invalidate pending access. Expired rows are removed when another invitation is created.
- Endpoints use no-store responses. Clients discard transient pairing state on cancellation/unmount, and revoke a returned session if the client leaves before completing pairing or cannot verify the wrapped key.

API: authenticated `POST /pairings`, `GET/DELETE /pairings/:id`, `POST /pairings/:id/approve`; unauthenticated secret-bound `POST /pairings/:id/join`, `/claim`, `/cancel`.

Validation includes live API tests on an isolated Neon branch (approval, wrong secrets, competing claims, cancellation, expiry, credential change, and logout) and a shared fixed encryption envelope verified by Swift and browser crypto tests. Real camera capture and physical-device HTTPS pairing still need a device acceptance check.

For browser acceptance, start the built website with an isolated test database, then run `RELAY_PAIRING_TEST_ORIGIN=http://127.0.0.1:3200 npm run test:pairing:web`. It creates and deletes a temporary account, pairs two browser sessions, verifies decryption of a saved agreement, checks lock, and saves screenshots under ignored `artifacts/`. It needs Playwright Chromium installed. Unit coverage also decodes an actual generated QR using the browser scanner library.
