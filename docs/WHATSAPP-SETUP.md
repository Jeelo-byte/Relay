# WhatsApp setup

Updated October 25, 2026. The website guide is available at `/docs`, linked from sign-in and Settings → Help & Feedback.

## Hosting

Manual agreements can stay local without messaging infrastructure. Live WhatsApp requires both a Matrix homeserver and the WhatsApp bridge. This setup currently runs them on the Mac; receiving messages depends on that Mac staying awake and online. Website hosting and Neon's encrypted agreement storage do not host those processes.

An always-on personal host is the next hosting option to evaluate. It needs persistent bridge sessions and media storage, private connectivity between bridge and homeserver, backups, and trusted HTTPS access from the app's devices. This has not been deployed or verified. Because the bridge decrypts messages, moving it changes which machine/operator handles the plaintext. The user must see that choice during setup.

Upstream requirements: [Mautrix Docker setup](https://docs.mau.fi/bridges/general/docker-setup.html). HTTPS configuration: [Synapse reverse proxy](https://element-hq.github.io/synapse/latest/reverse_proxy.html). The local-versus-hosted product recommendation is a project decision, not a claim that a hosted Relay service already exists.

## Connect on Mac

1. Run Relay, the local Matrix message server, and the WhatsApp bridge on the Mac. Keep the Mac awake and online for ingestion.
2. Open Settings → Connected Apps → Connect Messages or Choose Chats. Enter the configured message server address and Matrix credentials. Loopback HTTP is supported on this Mac; a physical phone needs a trusted HTTPS address.
3. Open WhatsApp → Open Bridge Setup on This Mac. In your own bridge management chat, request `login qr` if needed.
4. On your phone, open WhatsApp → Settings → Linked Devices → Link a Device. Scan the code and wait for a linked-account confirmation.
5. Choose conversations, then verify a real incoming message. A running process or a linked account is not proof of delivery.

## All conversations

Turn on **Include All WhatsApp Chats** in Connect Messages or Choose Chats. The choice persists on this device. Existing bridged WhatsApp rooms are enabled; newly discovered WhatsApp rooms are included automatically. Other networks stay opt-in. Pause individual chats with their switches. Turning the all-chat setting off stops automatic additions without changing existing per-chat choices. Signing out clears the setting.

Reconnecting the same message account preserves individual pauses. Connecting a different message account starts its chat choices off. Newly discovered or re-enabled chats refresh their initial timeline so a previously advanced sync cursor cannot skip their first message.

The bridge must allow the desired conversations too. This Mac's previous allowlist for one test group has been changed to permit all conversations. `sync groups` in your own WhatsApp bridge management chat discovers existing groups. Direct chats appear as new traffic reaches the bridge. Large group lists join gradually under server rate limits. Full historical WhatsApp import remains disabled.

## Check delivery and photos

Have someone send a new message to an included chat. Verify its sender, text, and time in Messages. The running, unlocked Mac app polls every three seconds independently of agreement sync. Discovery runs periodically; a new conversation can take longer to appear. File → Sync Now (`⌘R`) refreshes manually.

Images now load through authenticated Matrix media downloads, with loading, retry, and a 20 MB limit. Keep previews out of the shared network disk cache. Non-image attachments, expired media, and oversized photos may need WhatsApp. Photos do not yet appear in recaps as a live collage.

Right-click a text message on Mac, or touch and hold on iPhone/iPad, for **Create Agreement** and **Copy Message**. The repeated inline agreement buttons are removed. Review before saving or sending. Including chats does not automatically accept agreements or send replies. Local model processing remains separate.

## Troubleshooting

- Old message only: check opt-in, bridge filter, and Sync Now; use the rebuilt app with independent polling.
- Missing new chat: allow automatic inclusion or choose it, then allow discovery to finish. Direct chats with no new traffic may not be listed.
- Waiting for decryption: keep WhatsApp on the phone connected. The bridge needs keys or a resend; Relay replaces its placeholder when recovery arrives.
- Photo unavailable: Retry Photo, check the message-server connection, and verify the original opens in WhatsApp.
- Too Many Requests: room discovery resumes gradually; repeated reconnects do not speed it up.
- Phone/web mismatch: loopback addresses refer to the device using them. Live cross-device WhatsApp ingestion is not yet verified. The website currently shows saved source excerpts rather than full live rooms.

Messages are decrypted by the bridge on the Mac and stored in the local message server. Relay's local records are encrypted; Neon receives encrypted derived records and short source excerpts. Pairing credentials stay in ignored private storage.

Official server setup: [Mautrix WhatsApp](https://docs.mau.fi/bridges/go/whatsapp/).
