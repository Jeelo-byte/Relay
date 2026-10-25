# Relay hosting

The supported first host is the existing Mac, and the current demo runs on localhost. It runs the website/API and the message plane. Neon remains the encrypted derived-record store. This avoids a hosting purchase and keeps the bridge's decrypted history under the owner's control. Tailscale Serve is optional later for phones off this Mac; it is not required for the local demo. An always-on Linux machine can take over later using the same pinned containers, PostgreSQL dump, registration files and signing keys; that migration requires a restore rehearsal before changing the clients.

## Service boundaries

| Service | Address on the Mac | Data |
| --- | --- | --- |
| Website and API | 127.0.0.1:3100 | Browser app and encrypted account API |
| Synapse and bridges | 127.0.0.1:8008 | Decrypted chat history, media and bridge credentials |
| Relay gateway | 127.0.0.1:3400 | Routes website/API and Matrix client requests; blocks Synapse admin and federation paths |
| Neon | Configured DATABASE_URL | Authenticated ciphertext for agreements and recaps |
| Tailscale Serve | Your Mac's trusted HTTPS ts.net name | Private access for your signed-in devices |

The website talks directly to the Matrix client API at the same HTTPS origin. It never copies full conversations to Neon. Every browser login starts with all chats paused. Native chat consent remains separate. A browser keeps the latest 1,000 loaded messages per chat in memory; search covers loaded messages. Photos use authenticated, bounded downloads; SVG and encrypted attachments are unsupported. Reload or Lock clears tokens, messages, and photo URLs. A reply waiting for confirmation stays in page memory and is discarded on lock or reload. A server acknowledgement is not proof that the bridge delivered a message to WhatsApp.

## Start the Mac host

1. Keep the existing ignored `.env.local` with DATABASE_URL and PRELOGIN_HMAC_SECRET on the Mac. Keep `infra/matrix/private/` private; do not replace a working bridge session.
2. Run `npm ci`, `npm test`, and `npm run build` from the checkout.
3. Start the existing message stack with `bash scripts/live-docker.sh up -d` (only after its runtime configuration exists).
4. Run `bash scripts/start-host.sh`. Open http://localhost:3400 and check http://localhost:3400/healthz plus http://localhost:3400/_matrix/client/versions.
5. For automatic restart after signing into the Mac, run `node scripts/install-host.mjs --start`. Logs live in ignored `artifacts/host*.log`. The launch agent supervises both the web server and gateway. Remove it with `launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/app.relay.host.plist`, then remove that plist.

## Trusted HTTPS for phones and browsers

Install and sign into the official Tailscale app on the Mac and each phone/tablet. Enable HTTPS in your tailnet when prompted. Run:

```sh
tailscale serve --bg http://127.0.0.1:3400
tailscale serve status
```

Use the returned `https://...ts.net` address as both the Relay account server and message server. Restrict tailnet access to the owner's devices. Use **Serve**, which is private to the tailnet. No public hosting or Funnel is needed. Never bypass a certificate warning. The Mac must remain awake with Docker running; a launch agent does not run before the Mac user signs in. After an OS restart, verify Docker/Colima and the bridge containers have resumed too.

Tailscale's machine login and tailnet HTTPS enablement require the account owner. Until those are complete, loopback operation works but physical-device HTTPS reachability is unverified.

## Backups and recovery

Run `bash scripts/backup-message-plane.sh /absolute/path/relay-backup.tar.gz.enc` and enter a separate backup password when OpenSSL prompts. The script uses a logical PostgreSQL dump and captures the private bridge configurations/media, excluding live PostgreSQL physical files. It refuses to overwrite a backup and writes the final archive encrypted. Bridge configuration and media may change during capture; stop new linking/media ingestion for a coordinated recovery checkpoint. Keep at least one encrypted copy off the Mac, and keep its password separately. Avoid ordinary unencrypted cloud backups of `private/`.

To rehearse restore, decrypt into a private temporary directory on an isolated host, extract both archives, restore the SQL into an empty PostgreSQL instance of the same major version, and restore configuration/media without overwriting the new host's PostgreSQL directory. Keep restored bridges stopped until networking and credentials are checked; never run two active copies of a linked bridge session. Check login, room selection, a new incoming text/photo, and a confirmed send in a designated test chat before migrating devices. Backup generation alone does not establish a working restore.

## Acceptance evidence

Record production page/API reachability through the gateway, blocked admin paths, private HTTPS from a physical device, browser account unlock, same-account chat selection, new incoming text/photo, and reconnection after restarting the web/gateway/message services. Real outgoing traffic requires the user to choose a test chat and confirm its message. Do not count fixture tests or a container's running state as proof of live delivery.

References: [Tailscale Serve](https://tailscale.com/docs/features/tailscale-serve), [Serve CLI](https://tailscale.com/docs/reference/tailscale-cli/serve), [PostgreSQL logical backup](https://www.postgresql.org/docs/current/backup-dump.html), [Matrix client-server API](https://spec.matrix.org/latest/client-server-api/).
