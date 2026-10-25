# What works in Relay

Main at `5125b33`, checked October 25, 2026. A row is “Works” only when a test or a recorded run passed. A screen that merely exists is not counted as done.

| | Count |
| --- | --- |
| Areas with passing evidence | 10 |
| Built, not proven in use | 7 |
| Missing or blocked | 10 |

You can explore the sample workspace. You cannot demo live chats yet. The sample workspace, manual agreements, and encryption are trustworthy. A message from a real chat, accepted on iPad, then visible on the website, has not been run. Automatic sending is intentionally absent.

Counts of product areas on main. Source: tests, `docs/FINAL-DESIGN.md`, and GitHub Actions run 40167830184.

## Works

| Area | Evidence |
| --- | --- |
| Manual agreements | Create, edit, accept, dismiss, and complete. Money keeps exact minor units, date ranges validate, and unsupported pending changes stay pending. |
| Encryption on device | Argon2id, HKDF, and AES-GCM match between Swift and JavaScript. Tampered records are rejected. The local database stores ciphertext and a durable outbox. |
| Neon account sync | A recorded local run created an account, wrote ciphertext, and pulled it back. Conflicts, leases, tombstones, and device revocation with the current passphrase passed there. GitHub skips that live test. |
| Mac model extraction | Gemma 4 E2B extracted the ticket fixture and a cited recap on this Mac when the opt-in flag was on. The simulator stays in manual mode. |
| Recaps from chosen chats | A recap may use only chosen, non-deleted messages, and the quotes must match the source. Filters and date selection are in the app. |
| Events and recurrence | The week calendar is in the app. Daily, weekly, monthly, and yearly rules advance only when the rule is explicit. The next occurrence waits for review. |
| On-device messages | Search stays in chosen chats. A Matrix send is idempotent and stops without encryption or consent. The composer asks before sending. |
| People notes | Private notes are encrypted on the device, survive relaunch, and are kept out of the sync outbox. |
| Reminders and calendar files | Only accepted, open, unambiguous future items are planned. Calendar drafts escape text and fold long lines. Scheduling code talks to the system notification center. |
| Builds on main | GitHub Actions on commit `5125b33` passed `npm test`, the web production build, and `swift test` in 2m 50s. Live model, Neon, and Matrix tests are skipped in that workflow. |

## Built, not proven

| Area | What is still open |
| --- | --- |
| Latest iPhone and iPad flows | UI tests cover the sample collage, confirm-before-send, chat search, and accept-then-complete. The last note says the expanded iPad run was still being repeated. CI does not run those UI tests. |
| Live iMessage | The reader is tested on fixtures: opt-in, no history import, rich text, and dedupe. A real Messages database with Full Disk Access has not been recorded as passing. |
| A reminder on a device | The plan is unit tested. No device has been checked to confirm a notification appears, or that the body stays private. |
| Biometric unlock | Signed builds can use the current biometric set. An ad-hoc Mac build uses the login keychain and does not offer biometrics. |
| Same account in the browser | The web client can unlock and decrypt. Creating an agreement on the Mac and seeing that same record in the browser has not been run. |
| A linked chat account | Discord was running with no account linked. One local WhatsApp smoke test was recorded earlier and is not in the repo. The other networks are not linked. |
| Accessibility | Dynamic Type, VoiceOver, keyboard, pointer, dark mode, and increased contrast have not been walked through. |

## Does not work

| Area | Current limit |
| --- | --- |
| Live chat on the website | The site shows saved excerpts. It does not open a Matrix room or send a message. |
| Sending iMessage | Mac can copy a reply. It does not send, and it does not carry those chats to iPhone, iPad, or the server. |
| Other chat networks | Telegram, Signal, Slack, Google Messages, Messenger, and Instagram are not ready to link. Live traffic on each service is unverified. |
| Account recovery | Recovery codes can be checked. Unlock from a recovery code, passphrase change, account deletion, and key rotation are not finished. |
| Two devices editing one agreement | Optimistic conflicts are detected. Field-level merge, deletion wins, and rollback quarantine are not. |
| Real photos and attachments | The collage uses three sample images. Chat attachments stay unsupported placeholders. |
| Synced person notes | Notes stay on the device that wrote them. |
| Final onboarding and Settings | The five destinations are in place. The last design pass for onboarding and Settings is still open. |
| A signed phone or iPad | Simulator and Mac builds exist. No physical device is signed or installed. |
| Model evaluation and cloud mode | One Mac fixture passed. The ten-fixture gate, cloud provider, embeddings, OCR, and voice evidence are absent. |

`docs/FEATURES.md` and `docs/STATUS.md` lag the code. They still mark recurrence, chat search, device revocation, and CI as open. Those four now have tests or a green Actions run. `docs/FINAL-DESIGN.md` is the closer progress note, and it still does not claim the product is finished.
