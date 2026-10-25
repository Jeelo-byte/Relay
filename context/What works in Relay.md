# What works in Relay

Baseline: `main` at `1cede3a`, including implementation `5125b33`. Continuing on `codex/account-security`, updated October 25, 2026. A row is “Works” only when a test or a recorded run passed. A screen that merely exists is not counted as done.

| | Count |
| --- | --- |
| Areas with passing evidence | 14 |
| Built, not proven in use | 6 |
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
| On-device messages | Search stays in chosen chats. A Matrix send is idempotent and rejects encrypted rooms or withdrawn consent. The composer asks before sending. |
| People notes | Private notes are encrypted on the device, survive relaunch, and are kept out of the sync outbox. |
| Reminders and calendar files | Only accepted, open, unambiguous future items are planned. Calendar drafts escape text and fold long lines. Scheduling code talks to the system notification center. |
| Builds on main | GitHub Actions on commit `5125b33` passed `npm test`, the web production build, and `swift test` in 2m 50s. Live model, Neon, and Matrix tests are skipped in that workflow. |

| Redesigned iPhone and iPad flows | Four flows passed in each expanded run: manual creation, review/completion/persistence, chat search/source jump, and recap collage/sources. The send-confirmation flow then passed separately on each platform. iPhone final send result: `artifacts/iphone-review-send-r2.xcresult`; iPad: `artifacts/ipad-confirm-send-r3.xcresult`. The review sheet replaces the action popover that exposed the test issue. A fresh all-five iPhone run passed in 99.357 seconds on the security build (`artifacts/security-iphone-all.xcresult`). The fresh all-five iPad run also passed in 101.879 seconds (`artifacts/security-ipad-all.xcresult`). CI does not run UI tests. |
| Passphrase change | Current-passphrase proof required. Updates the salt, authentication verifier, and passphrase-wrapped data key atomically, retains the recovery wrap, and invalidates other sessions and leases. Live API tests passed; native integration passed in 5.125 seconds, including re-login and decrypting the original agreement with the unchanged data key. Wrong and stale proofs are rejected. Settings UI implemented; its end-to-end interaction test is pending. |

| Recovery-code reset | Unwraps the data key locally, replaces the passphrase and recovery wraps atomically, revokes existing sessions/devices, and returns a fresh device identity. Wrong, stale, and reused recovery proofs are rejected. Native recovery re-login decrypts the original agreement. New recovery code requires saved-code confirmation. |
| Account deletion | Exact handle and current passphrase required, followed by an explicit destructive confirmation in the app. Live API and native tests reject wrong proofs and verify that deleted account credentials and sessions stop working. Deletion uses disposable test accounts only. |

## Built, not proven

| Area | What is still open |
| --- | --- |
| Live iMessage | The reader is tested on fixtures: opt-in, no history import, rich text, and dedupe. A real Messages database with Full Disk Access has not been recorded as passing. |
| A reminder on a device | The plan is unit tested. No device has been checked to confirm a notification appears, or that the body stays private. |
| Biometric unlock | Signed builds can use the current biometric set. An ad-hoc Mac build uses the login keychain and does not offer biometrics. |
| Same account in the browser | The web client can unlock and decrypt. Creating an agreement on the Mac and seeing that same record in the browser has not been run. |
| A linked chat account | Discord was running with no account linked. One local WhatsApp smoke test was recorded earlier and is not in the repo. The other networks are not linked. |
| Accessibility | Dynamic Type, VoiceOver, keyboard, pointer, dark mode, and increased contrast have not been walked through. |

## Incomplete or awaiting setup

| Area | Current limit |
| --- | --- |
| Live chat on the website | The site shows saved excerpts. It does not open a Matrix room or send a message. |
| Sending iMessage | Mac can copy a reply. It does not send, and it does not carry those chats to iPhone, iPad, or the server. |
| Other chat networks | Synapse is healthy and seven bridge containers are running locally: WhatsApp, Discord, Signal, Slack, Google Messages, Messenger, and Instagram. This proves process readiness only. Linking and live traffic on each service remain unverified; Telegram still needs its API credentials. |
| Data-key rotation and offline unlock | Passphrase changes, recovery resets, and account deletion now pass live tests. Rotating the actual encryption data key and offline passphrase unlock remain unfinished. Security screens compile, but their full user-interaction flows still need separate UI tests. |
| Two devices editing one agreement | Optimistic conflicts, tombstones, high-water marks, and quarantine code exist; individual tombstone/high-water tests pass. Field-level three-way merging and the full cross-device conflict/rollback scenario remain unfinished or unverified. |
| Real photos and attachments | The collage uses three sample images. Chat attachments stay unsupported placeholders. |
| Synced person notes | Notes stay on the device that wrote them. |
| Final onboarding and Settings | The five destinations are in place. The last design pass for onboarding and Settings is still open. |
| Physical iPhone launch | Relay.app was signed with an Apple Development certificate and installed on Tj’s iPhone 16. The provisioning profile includes that phone and expires November 1, 2026. After developer trust was completed, the app launched successfully; a physical-device screenshot confirms Help & Feedback is rendered (`artifacts/tj-iphone-running.png`). This verifies installation/startup, not all feature flows on hardware. No physical iPad has been installed. |
| Model evaluation and cloud mode | One Mac fixture passed. The ten-fixture gate, cloud provider, embeddings, OCR, and voice evidence are absent. |

## Current verification

- Local full opt-in run: 41 Swift tests passed with no skips, including recovery and account deletion, Gemma extraction and cited recap generation, encrypted Neon agreement/recap round trips, and isolated Synapse sending. Latest full log: `artifacts/security-full-final-tests.log` (20.429 seconds).
- Final Node run: 8 tests passed, no skips, including live Neon security contracts and browser agreement/recap encryption validation. Log: `artifacts/security-live-node-final.log`.
- Native recovery and deletion passed again in the final full run, retaining the original DEK and decrypting previously written data. Sign-in now serializes with credential changes and recovery to prevent stale authentication from creating a session after a reset. One intermediate rerun hit the expected local signup rate limit; test transports now use isolated fixture identities, matching the Node tests, without changing production limits. The final rerun passed.
- Ciphertext audit: 19 blob rows inspected; no seeded plaintext markers found. Log: `artifacts/security-neon-audit.log`.
- Final macOS security build passed (`artifacts/security-final-macos-build.log`); the security code also compiled in the passing iPhone and iPad Xcode UI runs. Web production build passed after the browser recap fix (`artifacts/security-web-final-build.log`).
- October 25 device build: `artifacts/tj-iphone-build.log` passed using the Xcode application project, automatic provisioning, and the signed-in Personal Team. `codesign --verify --deep --strict` passed; `artifacts/tj-iphone-install.log` confirms installation on Tj’s physical iPhone 16. The initial launch was denied pending developer trust; after trust completed, launch succeeded (`artifacts/tj-iphone-launch.log`) and a screenshot confirmed the native UI (`artifacts/tj-iphone-running.png`). `scripts/run-iphone.sh` records the reproducible build/install/launch path. The prior bare-executable install error came from opening the root Swift package instead of `Relay.xcodeproj`.
- Normal simulator launch requires Xcode signing enabled for Keychain access. An unsigned build showed a vault alert even though isolated UI tests passed with an injected test key. Rebuilding with `CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-` opened the sample workspace on iPhone (`artifacts/working-iphone-xcode-signed.png`). The packaged Mac app also opened its sample Recaps workspace. Final iPad normal-launch verification remains pending.

## Next work

1. Add dedicated recovery, passphrase, and deletion UI flows. All five current general UI flows pass on both simulators.
2. Implement actual data-key rotation and offline passphrase unlock.
3. Complete web live conversations/sending, media, and remaining final-design behavior.
4. Keep account linking, physical signing, and real service traffic explicitly separate from fixture/sample evidence.

## Checkpoint and review

Implementation checkpoint: `4a7d554` on `codex/account-security`, pushed to GitHub with [draft PR #2](https://github.com/Jeelo-byte/Relay/pull/2). Both web and Apple CI jobs passed in run `40170716006`. Local live tests remain separate from CI, which skips external-service opt-ins.

This tracker is the current evidence summary. `docs/STATUS.md` now points here; historical verification documents describe their own earlier checkpoints. The product is not yet complete.
