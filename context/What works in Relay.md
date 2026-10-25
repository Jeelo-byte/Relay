# What works in Relay

Baseline: `main` at `62f2cdc`, updated October 25, 2026. Earlier evidence through `5125b33` and the account-security merge `3cceeaa` remains below. A row is “Works” only when a test or a recorded run passed. A screen that merely exists is not counted as done.

| | Count |
| --- | --- |
| Areas with passing evidence | 16 |
| Built, not proven in use | 6 |
| Missing or blocked | 8 |

The Mac now displays a real incoming WhatsApp message from the single group selected by the user. The sample workspace and manual agreements also have passing evidence. A real-chat agreement accepted on iPad and visible on the website has not been run. Unattended sending is still absent. The Mac has a reviewed iMessage send path and the local website can confirm a Matrix reply, but outgoing delivery on a real messaging network was not verified for this checkpoint.

Counts of product areas at the current branch checkpoint. Source: tests, `docs/FINAL-DESIGN.md`, and GitHub Actions run 40167830184.

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
| Builds on main | GitHub Actions on commit `62f2cdc` passed the web job (`npm test` and the production build) and `swift test` in 2m 45s (run `40180451095`). Live model, Neon, and Matrix tests are skipped in that workflow. The Mac Xcode target includes the iMessage send path, contact import, and Automation entitlements. That workflow does not package the Mac app. |

| Redesigned iPhone and iPad flows | Four flows passed in each expanded run: manual creation, review/completion/persistence, chat search/source jump, and recap collage/sources. The send-confirmation flow then passed separately on each platform. iPhone final send result: `artifacts/iphone-review-send-r2.xcresult`; iPad: `artifacts/ipad-confirm-send-r3.xcresult`. The review sheet replaces the action popover that exposed the test issue. A fresh all-five iPhone run passed in 99.357 seconds on the security build (`artifacts/security-iphone-all.xcresult`). The fresh all-five iPad run also passed in 101.879 seconds (`artifacts/security-ipad-all.xcresult`). CI does not run UI tests. |
| Passphrase change | Current-passphrase proof required. Updates the salt, authentication verifier, and passphrase-wrapped data key atomically, retains the recovery wrap, and invalidates other sessions and leases. Live API tests passed; native integration passed in 5.125 seconds, including re-login and decrypting the original agreement with the unchanged data key. Wrong and stale proofs are rejected. Settings UI implemented; its end-to-end interaction test is pending. |

| Recovery-code reset | Unwraps the data key locally, replaces the passphrase and recovery wraps atomically, revokes existing sessions/devices, and returns a fresh device identity. Wrong, stale, and reused recovery proofs are rejected. Native recovery re-login decrypts the original agreement. New recovery code requires saved-code confirmation. |
| Account deletion | Exact handle and current passphrase required, followed by an explicit destructive confirmation in the app. Live API and native tests reject wrong proofs and verify that deleted account credentials and sessions stop working. Deletion uses disposable test accounts only. |
| Physical iPhone launch | Relay.app was signed with an Apple Development certificate and installed on Tj’s iPhone 16. The provisioning profile includes that phone and expires November 1, 2026. After developer trust was completed, the app launched successfully; a physical-device screenshot confirms Help & Feedback is rendered (`artifacts/tj-iphone-running.png`). The user also confirmed it works. This verifies installation/startup, not all feature flows on hardware. No physical iPad has been installed. |

| Live WhatsApp on Mac | October 25: local account authenticated, WhatsApp bridge reported linked, and the user’s exact test marker was found in the selected group’s Matrix room. Enabled only that group in the Mac app; its Messages screen visibly rendered the incoming test message. Screenshot: `artifacts/mac-whatsapp-live-message.png` (ignored/private). Bridge portal creation is restricted to the chosen group and backfill is off. No outgoing group message was sent; other networks and cross-device delivery remain unverified. |

## Built, not proven

| Area | What is still open |
| --- | --- |
| Live iMessage | The reader and send path are tested on fixtures: selected-chat cursors, rich text, dedupe, exact chat routing, recent-history isolation, script escaping, and uncertain-send reconciliation. Contact import, vCard import, and profile linking have fixture tests. A real Messages database read or send still needs macOS Full Disk Access and Automation. None was sent. |
| Live chats on the local website | The site can connect to the local message server, include chats, refresh, search loaded messages, show photos, and confirm replies. Lock, reload, and leaving the page drop the message session. Client tests cover encryption, consent, dedupe, and media bounds. A repeated live WhatsApp delivery check in the browser was not recorded for `62f2cdc`. |
| A reminder on a device | The plan is unit tested. No device has been checked to confirm a notification appears, or that the body stays private. |
| Biometric unlock | Signed builds can use the current biometric set. An ad-hoc Mac build uses the login keychain and does not offer biometrics. |
| Same account in the browser | The web client can unlock and decrypt. Creating an agreement on the Mac and seeing that same record in the browser has not been run. |

| Accessibility | Dynamic Type, VoiceOver, keyboard, pointer, dark mode, and increased contrast have not been walked through. |

## Incomplete or awaiting setup

| Area | Current limit |
| --- | --- |
| Sending iMessage on a real Mac | The Mac app can send a reviewed text reply through Messages after Automation permission, and it can import and link contacts. Those paths are fixture-tested. Full Disk Access and Automation were not granted for this checkpoint, and no real message was sent. iMessage chats still do not carry to iPhone, iPad, or the server. |
| Other chat networks | Synapse is healthy and seven bridge containers are running locally: WhatsApp, Discord, Signal, Slack, Google Messages, Messenger, and Instagram. This proves process readiness only. WhatsApp incoming traffic is now verified on Mac for one selected group. Other services remain unlinked/unverified; Telegram still needs its API credentials. |
| Data-key rotation | Passphrase changes, recovery resets, and account deletion pass live tests. Offline passphrase unlock after an online sign-in is implemented, with a unit test for the cached wrap. Rotating the actual encryption data key is not implemented. Security screens compile, but their full user-interaction flows still need separate UI tests. |
| Two devices editing one agreement | Optimistic conflicts, tombstones, high-water marks, and quarantine code exist; individual tombstone/high-water tests pass. Field-level three-way merging and the full cross-device conflict/rollback scenario remain unfinished or unverified. |
| Real photos and attachments | The collage uses three sample images. Chat attachments stay unsupported placeholders. |
| Synced person notes | Notes stay on the device that wrote them. |
| Final onboarding and Settings | WhatsApp has a four-step setup in the app: Get started, Link WhatsApp, Choose chats, and Check delivery. It is shared by first launch and Settings. Figma onboarding for every other messaging service was not completed. The Mac app uses the Figma desktop workspace: a persistent sidebar and the five destinations. iPhone and iPad keep their existing navigation. Release must still open into the full Figma onboarding flow, with no automatic sample conversations, agreements, people, photos, or recaps. See the acceptance requirements below. |
| Model evaluation and cloud mode | One Mac fixture passed. The ten-fixture gate, cloud provider, embeddings, OCR, and voice evidence are absent. |

## Current verification

- Local full opt-in run: 41 Swift tests passed with no skips, including recovery and account deletion, Gemma extraction and cited recap generation, encrypted Neon agreement/recap round trips, and isolated Synapse sending. Latest full log: `artifacts/security-full-final-tests.log` (20.429 seconds).
- Final Node run: 8 tests passed, no skips, including live Neon security contracts and browser agreement/recap encryption validation. Log: `artifacts/security-live-node-final.log`.
- Native recovery and deletion passed again in the final full run, retaining the original DEK and decrypting previously written data. Sign-in now serializes with credential changes and recovery to prevent stale authentication from creating a session after a reset. One intermediate rerun hit the expected local signup rate limit; test transports now use isolated fixture identities, matching the Node tests, without changing production limits. The final rerun passed.
- Ciphertext audit: 19 blob rows inspected; no seeded plaintext markers found. Log: `artifacts/security-neon-audit.log`.
- Final macOS security build passed (`artifacts/security-final-macos-build.log`); the security code also compiled in the passing iPhone and iPad Xcode UI runs. Web production build passed after the browser recap fix (`artifacts/security-web-final-build.log`).
- October 25 live messaging: Mac message-server login and explicit opt-in for one user-selected WhatsApp group passed. The actual incoming test message rendered in the native Messages screen. Pairing and account credentials remain in ignored private storage; no credentials or personal conversation screenshots are committed. Sending, reconnect/relaunch, recaps, and cross-device verification are separate remaining tests.
- October 25 device build: `artifacts/tj-iphone-build.log` passed using the Xcode application project, automatic provisioning, and the signed-in Personal Team. `codesign --verify --deep --strict` passed; `artifacts/tj-iphone-install.log` confirms installation on Tj’s physical iPhone 16. The initial launch was denied pending developer trust; after trust completed, launch succeeded (`artifacts/tj-iphone-launch.log`) and a screenshot confirmed the native UI (`artifacts/tj-iphone-running.png`). `scripts/run-iphone.sh` records the reproducible build/install/launch path. The prior bare-executable install error came from opening the root Swift package instead of `Relay.xcodeproj`.
- Normal simulator launch requires Xcode signing enabled for Keychain access. An unsigned build showed a vault alert even though isolated UI tests passed with an injected test key. Rebuilding with `CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-` opened the sample workspace on iPhone (`artifacts/working-iphone-xcode-signed.png`). The packaged Mac app also opened its sample Recaps workspace. Final iPad normal-launch verification remains pending.

## Next work

Deliver one complete, verified item, update this file with its evidence, and push that checkpoint to GitHub before the next item. Do not mark a design, a compiling screen, or a running container as a working feature.

| Order | Deliverable | Status and completion gate |
| --- | --- | --- |
| 1 | WhatsApp sync, photo previews, message actions, and real-data-only startup | Pushed as `05e9a10` to `codex/account-security` and draft PR #2. See evidence below. A fresh visual inspection of the running Mac app remains open; this is separate from passing live read-only ingestion and simulator interactions. |
| 2 | Friendly guided connections | WhatsApp’s four-step setup is in the app for first launch and Settings: Get started, Link WhatsApp, Choose chats, and Check delivery. It includes save/resume, set up later, pairing/expiry/reconnect states, chat search, and a real incoming-message gate. Pairing-state and resume tests cover the logic. A live phone scan in this session was not repeated. Figma onboarding for every other messaging service was not completed; those services still use their existing setup screens. |
| 3 | Hosting and reachability | Local Mac hosting is documented and scripted: website on 127.0.0.1:3100, loopback gateway on 127.0.0.1:3400, encrypted message-plane backup, and an optional launch agent. The current demo stays on localhost. Tailscale HTTPS for phones was deferred and is not verified. |
| 4 | Live website interface | The local site can connect to the message server, include chats explicitly, refresh, search loaded messages, show photos, and confirm replies. Lock, reload, and leaving the page drop the message session. Browser checks against the running WhatsApp room were started in the earlier session; this pass rechecked the client tests and the lock/unmount path in code. |
| 5 | Complete website documentation | Initial WhatsApp setup guide built. Keep it current with linking, host requirements, privacy, chat controls, images, errors, reconnects, cross-device setup, and service-specific availability. Document every finished checkpoint as it ships. |
| 6 | Final polish across platforms | Initial web motion added: 160 ms page-entry transitions and 120 ms navigation feedback, disabled by Reduce Motion. The Mac app now uses the Figma desktop workspace while keeping the tested iMessage outbox. Chat id and message text are Apple event parameters. Broader polish remains pending: follow the existing Figma designs and verify keyboard, VoiceOver, large text, dark mode, compact layouts, and empty/error states across platforms. |
| 7 | Remaining security and sync work | Offline passphrase unlock is implemented for a device that has signed in online, with a unit test for the cached wrap. Passphrase change refreshes that cache. Data-key rotation, dedicated security UI tests, and field-level multi-device conflict handling remain unfinished. |
| 8 | Remaining product features and evidence | iMessage on Mac can read chosen chats and send through Messages after Automation permission; contact import and manual profile links are in People, with fixture tests. A real read or send still needs Full Disk Access and Automation. Neither grant was used, and no real iMessage was sent. Live attachments/recap galleries, synced person notes, reminder delivery, model evaluation/cloud mode, and the outstanding acceptance requirements in the build plan remain open. |

October 25 user clarification: service connection must become user friendly, the project needs an explicit server-hosting plan, the website must have both documentation and a working live interface, and final polish includes small navigation animations. These are implementation requirements; they are not complete merely because designs exist.

## Release onboarding and clean workspace requirements

User requirement, October 25: remove sample data from the final user experience and provide friendly onboarding that follows the final Figma design. This is required work, not marked complete.

- Fresh release install contains no fictional chats, people, agreements, recaps, or sample photos. Remove the enabled `-demo` argument from the release/distribution path; fixtures may remain in tests or an explicitly separate developer demo workspace. Never remove real user records as part of sample cleanup.
- Follow the Figma sequence: [Welcome](https://www.figma.com/design/10XdD87FnyxKWFoeF0zogy/Relay?node-id=7-5634), [Connections](https://www.figma.com/design/10XdD87FnyxKWFoeF0zogy/Relay?node-id=7-5692), [Choose Chats](https://www.figma.com/design/10XdD87FnyxKWFoeF0zogy/Relay?node-id=7-5767), and [Preferences](https://www.figma.com/design/10XdD87FnyxKWFoeF0zogy/Relay?node-id=7-5862). The final Figma design remains the visual source across iPhone, iPad, Mac, and web; this requirement does not imply the current screens match it completely.
- New/existing-account entry points, actual service linking, searchable chat opt-in, preference persistence, and Set Up Later must work. Figma’s optional sample-exploration copy must be omitted from the normal release flow to honor the user's clean-workspace requirement.
- Keep setup brief and resumable. Explain local message storage and request system permissions when the related feature is used. Every live chat starts off; review is required before saving suggestions or sending replies. No large model download may block entry.
- Use the established warm background, maroon accent, semantic dark colors, rounded cards, system controls, and adaptive navigation. Verify against Figma renders on all four platforms, including large text, VoiceOver, keyboard input, and empty/error/reconnect states.
- Required evidence: fresh install starts onboarding without samples; skipping lands in a truthful empty state; completion and relaunch retain preferences; connecting real data never mixes in fixtures; returning users are not forced through setup again. First live-message ingestion must work from this clean workspace.

Figma was re-read October 25 (session `3d038742-4354-47c5-8f3f-e35e9a3d285f`), including the Welcome design context and screenshot. Apple onboarding guidance was also checked. Implementation and visual acceptance remain pending.

## Checkpoint and review

Security implementation checkpoint: `4a7d554` on `codex/account-security`, pushed to GitHub with [draft PR #2](https://github.com/Jeelo-byte/Relay/pull/2). Both web and Apple CI jobs passed in run `40170716006`. Local live tests remain separate from CI, which skips external-service opt-ins.

This tracker is the current evidence summary. `docs/STATUS.md` now points here; historical verification documents describe their own earlier checkpoints. The product is not yet complete.

## October 25 follow-up: real WhatsApp and setup

User requested automatic incoming updates, all WhatsApp conversations, actual image display, and agreement actions in a message context menu. The message refresh has been separated from account sync and runs while the Mac app is unlocked. All-chat inclusion is now an explicit saved setting with automatic discovery and individual pauses. Bridge portal creation no longer targets only the original test group; existing group discovery returned 73 groups and imports under server join limits. This does not import the full WhatsApp history.

The live read-only WhatsApp integration test passed, including an authenticated image download. The latest Swift run is logged in `artifacts/whatsapp-full-tests.log`; final UI checks and build evidence are recorded after verification. Cross-device live chat, web live chat, videos, full media galleries, and automatic agreement acceptance are not claimed.

New requirements and current controls: [WhatsApp setup](../docs/WHATSAPP-SETUP.md) and [guided onboarding](../docs/ONBOARDING.md). The user explicitly requires **real data only** now: remove normal sample entry points, demo launch defaults and stored known fixture records while preserving real data. The app now includes the four-step WhatsApp setup for first launch and Settings. Figma onboarding for every other messaging service was not completed. Website documentation is at `/docs`.

## October 25 implementation checkpoint: WhatsApp and clean startup

- Incoming refresh runs every three seconds while the Mac workspace is unlocked, independently of encrypted-account sync. All-chat inclusion is saved; discovery preserves per-chat pauses and reconnecting the same message account retains them. A new message account starts with chat consent off. New or re-enabled chats reset their initial sync cursor so their first messages cannot be skipped. Consent changes during a request cannot overwrite that reset.
- WhatsApp decryption placeholders recover into text or image messages, including replacements bundled into an initial sync. Regression coverage checks sender identity, deduplication, original timestamps, paused chats, persistence, and preservation of deleted state.
- Authenticated photos have loading/retry states and a 20 MB bound. Message actions use the system context menu and accessibility actions. Normal native and web entry points no longer offer samples; launch scripts and Xcode defaults no longer seed them. Cleanup removes fixture-only source records and keeps real messages, manual agreements, mixed-source agreements, and private notes.
- Website `/docs` now explains WhatsApp linking, chat selection, delivery checks, photos, agreement actions, privacy, troubleshooting, and server requirements. It is linked from web sign-in and web Help & Feedback. Localhost host scripts are in the tree. The website can open a local Matrix session. Tailscale HTTPS and an always-on host remain unverified.

Verification on October 25:

| Check | Result |
| --- | --- |
| `RELAY_VERIFY_WHATSAPP=1 swift test` | 48 executed, 44 passed, 4 unrelated external-service/model tests skipped; zero failures. Live read-only WhatsApp incoming text and authenticated image download passed. Log: `artifacts/whatsapp-checkpoint-tests.log`. |
| `npm test` | 7 passed, 1 live Neon test skipped; zero failures. Log: `artifacts/whatsapp-checkpoint-node.log`. |
| `npm run build` | Passed, including `/docs`. Log: `artifacts/whatsapp-checkpoint-web-build.log`. Production guide loaded in the browser, including hosting guidance and truthful current-platform limits. |
| iPhone UI | Both new tests passed: fresh empty startup/local relaunch and long-press → Create Agreement → editor. 43.155 seconds; `artifacts/whatsapp-checkpoint-iphone.xcresult`. |
| iPad UI | The same two tests passed in 66.009 seconds; `artifacts/whatsapp-checkpoint-ipad.xcresult`. |
| Mac package | `scripts/package-mac.sh artifacts/Relay.app` and strict signature verification passed. Log: `artifacts/whatsapp-checkpoint-mac-build.log`. Native screen inspection timed out after relaunch, so a fresh Mac photo-preview/right-click visual check is still unverified. |

No message was sent to a real WhatsApp conversation during this checkpoint. Credentials, private chat data, and ignored verification artifacts are excluded from Git. Continue with the ordered roadmap above; designs alone do not mark the remaining items complete.

### Web motion follow-up

Added short page-entry transitions (160 ms, 4 px) to workspace destinations, sign-in, and the setup guide, plus 120 ms color feedback in navigation. Content refreshes do not restart the transition. The browser's Reduce Motion preference disables these animations and transitions. Production build passed (`artifacts/web-motion-build.log`); browser inspection confirmed `relay-page-enter` at `0.16s`, then `none` with Reduce Motion enabled. The compact guide measured 342 px of content at a 390 px viewport with 17 px body text and no horizontal overflow. Native page transitions and the broader accessibility/polish pass remain open.

## October 25 main checkpoint

`62f2cdc` is on `main`. GitHub Actions run `40180451095` passed the web job and `swift test`. This checkpoint records what that commit contains. It does not add a new live-device run.

- iMessage on Mac has a reviewed send path, contact import, and profile linking. Fixture tests cover send routing, uncertain-send reconciliation, vCard import, and link transfer. The Mac target includes Automation entitlements. A real read or send still requires Full Disk Access and Automation, and none was sent.
- The local website can connect to the message server, include chats, refresh, search loaded messages, show photos, and confirm replies. Lock, reload, and leaving the page drop that session. Docker notes are in the setup guide. A repeated live browser delivery check was not recorded here.
- WhatsApp setup in the app is four steps: Get started, Link WhatsApp, Choose chats, and Check delivery. Offline unlock works after an online sign-in on that device. Localhost hosting is scripted with `scripts/start-host.sh`, a loopback gateway, and an encrypted message-plane backup. Tailscale HTTPS was left for later.
- Data-key rotation and field-level multi-device conflict merge are not implemented. Figma onboarding for every messaging service was not completed. The Mac desktop workspace is in the app. The iMessage send path remains the tested outbox from `62f2cdc`; message text is passed to Messages as an Apple event parameter, and a second competing sender was not kept.
- `.cursor/settings.json` is uncommitted. It only enables the Figma editor plugin and is not an app setting.
