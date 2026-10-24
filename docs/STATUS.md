# Relay integration status

Verified on October 24, 2026:
- Private GitHub repository: https://github.com/Jeelo-byte/Relay. Development branch: codex/native-demo.
- Xcode 27.1 is installed. iOS 27.0 and iOS 27.1 runtimes are installed. Relay iPhone 17 Pro and iPad Pro M4 simulators booted.
- First native app build passed for macOS and iOS Simulator. Both simulator apps launched.
- 10 Swift tests passed: cross-language crypto vector, Unicode KDF normalization, AES-GCM tamper rejection, padding, recovery code, encrypted local database/outbox, evidence normalizer, review transitions/totals, room opt-in and merge history.
- 6 Node tests passed, including a live Neon API test for accounts, wrong credentials, ciphertext writes/pull, optimistic conflicts, leases, tombstones and account isolation by bearer session.
- Neon project soft-unit-14813306 (Relay), development branch br-crimson-dew-b4uf3v3i. The main branch is unchanged.

Still being integrated and verified:
- Gemma 4 E2B through the VLM loader, pinned model revision 238767527555cb75a05732a84dff5d6ba0dd6809. No inference claim until weights load and extraction passes.
- XCUITest interaction checks and rebuilt screenshots after first visual review fixes.
- Native account creation → encrypted sync → browser unlock on the same real account.
- Matrix server and bridges. A working server and account links have not been supplied. Docker is installed but its daemon was stopped at initial inspection.
- Physical-device signing and hardware inference checks. No physical iPad or iPhone is connected yet.
