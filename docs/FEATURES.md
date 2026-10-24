# Feature verification checklist

A checked item must have passing behavior evidence; compilation alone is not sufficient. User requested all intended features and tests, beyond the initial hackathon cut line. Explicitly removed features remain excluded.

## Core agreement workflow
- [x] Two-axis review and lifecycle model (shared tests)
- [x] Per-currency totals exclude suggestions and completed obligations (shared tests)
- [x] Manual create/edit/dismiss/restore/complete implementation
- [ ] Manual workflow verified by XCUITest on iPad and iPhone
- [ ] All obligation types and fields editable, including instant/range dates and recurrence
- [ ] Source trail jump, edits/deletions, exact quotes verified end to end
- [ ] Pending changes apply/ignore, partial payments and disputes
- [ ] Field-level three-way merge, deletion wins, rollback quarantine verified across devices

## Messaging plane
- [x] Synapse running locally, loopback binding, registrations disabled
- [x] Discord bridge running without linked account
- [ ] WhatsApp bridge ready, account not yet linked
- [ ] Telegram bridge ready, API credentials/account not yet linked
- [ ] Signal bridge ready, account not yet linked
- [ ] Slack bridge ready, account not yet linked
- [ ] Google Messages bridge ready, account not yet linked
- [ ] Messenger bridge ready, account not yet linked
- [ ] Instagram bridge ready, account not yet linked
- [ ] Bridge status, per-room opt-in, backfill, pagination, attachments and unsupported states
- [ ] Importer fallback for WhatsApp text and Telegram JSON
- [ ] Live messages on each linked service verified (requires account setup)

## Models and pipeline
- [x] Pinned Gemma 4 E2B loads and extracts on the Mac (hardware test passed, 8.411 s including cached load)
- [x] Validated amount, due date, party mapping and both commitment/acceptance quotes for ticket fixture
- [ ] Ten-fixture demo gate and full evaluation corpus
- [ ] Cancellation, resume, checksum, disk/network/thermal states
- [ ] Complete reconcile and dedupe rules, online leases and offline handling
- [ ] Foundation Models triage fallback
- [ ] Cloud provider mode with consent, pseudonymization, limits, repair and retries
- [ ] Suggested replies (copy only), exact evidence citations
- [ ] Ask Your Chats (local search with cited answers)

## Security, account and sync
- [x] Swift/JavaScript Argon2id + HKDF + AES-GCM vector compatibility
- [x] Authenticated encryption rejects tampering, swapped IDs and versions
- [x] Encrypted local records and durable dirty records (GRDB)
- [x] Native account creation/login and encrypted Neon round trip pass
- [x] Live API tests for sessions, conflicts, leases and tombstones pass
- [x] Neon ciphertext audit passes
- [ ] Browser unlock → decrypt native agreement → accept → reload verified
- [ ] Recovery unlock and passphrase change
- [ ] Account/device revocation, account deletion, key rotation
- [ ] Biometry-current-set gate, lock timeout, privacy covers and notification privacy
- [ ] Local notification scheduling within platform limits

## Platform and delivery
- [x] Initial native Xcode builds and launches on macOS/iOS Simulator
- [x] Web production build passes
- [ ] Updated native builds after model and messaging integration
- [ ] Dynamic Type, VoiceOver, keyboard, pointer, dark/light/increased-contrast tests
- [ ] Screen state gallery and required empty/loading/offline/error states
- [ ] HTTPS for physical-device demo and signed-device builds
- [ ] GitHub checkpoints, PR and CI verification
- [ ] Rehearsed demo, screenshots, runnable instructions and known-limits report

## Later-plan features requested under “all features”
- [ ] Recurrence completion/next occurrence, calendar drafts
- [ ] Local embeddings for semantic search
- [ ] OCR/voice evidence, link/media vault, mentions, reply debt and topic threads

Excluded by the plan: briefs, recaps, digests, Ollama/local model servers, auto-send, automatic contact merging, plaintext Neon content, Redis, and the deferred Beeper/E2EE importer architecture.
