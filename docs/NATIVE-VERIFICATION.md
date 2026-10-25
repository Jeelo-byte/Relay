# Mac and iPad native checkpoint — October 24, 2026

Source: `codex/native-demo`, GitHub PR #1, commit `274fd1d6e76bd48cbde3e1f6750f793ebdeee918`.
The `main` branch is an older skeleton; the draft PR contains the working prototype.

## Delivered in this checkpoint

- A runnable Apple Silicon Mac application, `Relay.app`, alongside this source folder.
- Native editing for calendar dates, date/time deadlines, date ranges, recurrence notes,
  conditions, places, multiple obligations, and the recipient of each obligation.
- Decimal-safe money entry with ISO currency precision, including rejecting fractional JPY.
- Save failure keeps the editor open instead of silently dismissing it.
- People navigation works through callbacks on Mac and an explicit navigation path in compact layout.
- Command-K opens agreement search. Dashboard sorting ignores closed obligations and uses
  last-edited order when deadlines tie.
- Reviewed pending changes support each obligation's due date, amount, and place.
  Applying completion/cancellation updates the obligation statuses too. Unsupported changes
  stay pending and display an error rather than being falsely marked applied.
- Extraction keeps the actual supporting quote, including a quote beyond a long preamble;
  pseudonymized quotes restore names/contact placeholders from a per-message map.
- Follow-up change/completion messages qualify for processing when their room has an open
  agreement. Prompts now include the existing obligations, not only a title and lifecycle.
- Matrix refresh runs alongside foreground account sync and guards overlapping requests.
- Extraction leases are completed only after local pending writes have drained.
- Account-bound synchronization checks after awaits prevent a late response from repopulating
  a signed-out workspace; edits made during a conflict retry stay dirty for the next push.
- Account inactivity lock settings, locked menu-bar privacy, and a Keychain biometric gate
  tied to the current enrolled biometric set. Biometric behavior requires device testing.
- Swift 6.0/6.1 can build Manual mode without resolving the incompatible Gemma runtime;
  Swift 6.2+ retains the pinned MLX dependencies. The UI states the actual availability.

## Verification performed here

Environment: Xcode 16.4; Swift 6.1.2; Apple Silicon; macOS SDK 15.5; iOS Simulator SDK 18.5.
Earlier repository status notes describing Xcode 27 and previous live checks are historical
claims from the imported prototype, not observations made on this Mac during this checkpoint.

- macOS application and shared library compiled.
- Initial native checkpoint: `swift test` reported 25 passed, 0 failed, 2 skipped (27 total).
- Skipped: opt-in live Gemma extraction and live Neon round trip; neither was claimed as verified.
- Included regressions: amount precision and invalid fractional yen; date-range validation;
  reviewed completion; changes on the second obligation; unsupported pending changes;
  high-water marks surviving tombstones/relaunch; exact quote spans and placeholder restoration.
- iOS/iPad-target application compiled for `arm64-apple-ios17.0-simulator` with the iOS 18.5 SDK.
  This is a compile/link check, not an iPad interaction test. The SwiftPM link emitted a sysroot
  warning; use the Xcode project for device installation and final platform verification.
- Packaged Mac app passed `codesign --verify --deep --strict` with a local ad-hoc signature.
  It is not notarized for distribution.
- `git diff --check` passed.
- A later retry successfully accessed both Relay and Simulator with the existing permissions.
- Visual Mac smoke check: launch → Sample Workspace → ticket detail/source trail passed.
  Screenshot: `Relay-preview.png` alongside the application. iPad interaction checks remain pending.
- That visual check found and fixed a startup Keychain error (-34018) in the ad-hoc Mac build.
  Debug builds without a provisioned app identity now use the macOS login Keychain; signed
  release builds retain Data Protection Keychain. Settings displays the actual key storage.
  Biometric unlock is unavailable for that unprovisioned development configuration.

## Run

Open the accompanying `Relay.app`. Choose **Explore the Sample Workspace** to review the
fictional examples, or **Start on This Device** for manual use. Creating a real account needs
an actual configured Relay API endpoint; the local default is not a deployed service.

For development, open `Relay.xcodeproj` and select a Mac or iPad destination. On the command line:

```sh
swift test
swift run Relay
bash scripts/package-mac.sh
```

Local model inference requires a Swift 6.2+ build and a physical Apple Silicon device. The
current prebuilt Mac app uses Manual mode; it does not pretend to run Gemma.
The build used the exact upstream GRDB 7.10.0 commit via a local shallow mirror to avoid
fetching the entire repository history. That machine-specific mirror is excluded from the
source archive; normal builds resolve the original GitHub URLs.

## Remaining native and integration work

This checkpoint improves the native prototype; it does **not** complete the full v5 plan.

- Physical iPad signing, interaction/VoiceOver/Dynamic Type checks, actual biometric enrollment
  changes, and screenshot/rehearsal verification.
- Local Gemma hardware gate, ten-fixture evaluation, full download/resume/hash/space/thermal
  state machine, cancellation/background GPU validation and model unloading.
- Live bridge accounts, HTTPS/Tailscale access, continuous Matrix/backfill/event-order tests,
  and automatic extraction scheduling. Foreground refresh is polling, not a long-poll loop.
- Full field-level three-way conflict merging, delete/restore workflow, atomic Matrix cursor
  commits, account recovery/passphrase-change flows and offline passphrase unlock.
- Cloud consent/provider implementation, local notifications, shared schema/code generation,
  state gallery and the full edge-case/evaluation corpus.
- Recurrence is a stored/displayed note, not automatic creation of future obligations.
- Web work remains secondary to the requested native priority.

## Additional integration checkpoint

The native suite now reports 27 passing tests and two skipped live checks. Both Mac and iPad simulator targets compile. iMessage support uses a read-only Mac-local reader with explicit per-conversation opt-in and new-message cursors; see IMESSAGE.md for setup and current limits. Live iMessage verification remains pending.

A local WhatsApp smoke test verified message ingestion and manual agreement creation. Runtime accounts, credentials, message databases, test conversation records, screenshots, logs, and machine-specific configuration are excluded from version control.
