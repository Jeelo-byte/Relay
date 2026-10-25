# Updated baseline verification

The user confirmed commit `26d758c` on `origin/codex/native-demo` is the new authoritative version. It was fast-forward pulled before further work. Earlier unfinished local changes remain in the Git stash named `Relay local feature work before teammate pull`; they have not been reapplied.

Further work starts on `codex/finish-relay`, based directly on that commit.

Verified on this workspace with Xcode 27.1 / Swift 6.4:

- `swift test`: 27 passed, 2 opt-in integration tests skipped (29 total).
- `RELAY_VERIFY_MODEL=1 RELAY_VERIFY_NEON=1 swift test --filter IntegrationTests`: both live tests passed. Cached Gemma extraction completed in 8.547 s; the native encrypted Neon round trip completed in 3.077 s.
- `node --env-file=.env.local --test backend/api.test.mjs packages/normalize/normalize.test.mjs`: all six tests passed, including the live Neon API test.
- Regenerated the Xcode project from `project.yml`. This added the new iMessage connection view to the native app target, which was absent from the checked-in project.
- `xcodebuild -project Relay.xcodeproj -scheme Relay -destination 'platform=macOS' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build`: passed.

`Package.resolved` now includes the conditional MLX dependencies selected by Swift 6.2+ while retaining the teammate's pinned dependency versions. No app features were restored from the archived pre-pull work.

These checks do not prove live iMessage access, third-party bridge account linking, physical-device behavior, or completion of the full build plan. The teammate's documented remaining work in `docs/NATIVE-VERIFICATION.md` is still relevant.
