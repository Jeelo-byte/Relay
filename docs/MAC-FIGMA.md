# macOS Figma implementation

Base: `codex/account-security` at `a2a2279`, which includes the latest main branch and the subsequent security and messaging changes.

Reference: [Relay final product design, macOS page](https://www.figma.com/design/10XdD87FnyxKWFoeF0zogy/Relay?node-id=3-5).

The Mac workspace now uses a persistent 240-point sidebar, selected conversation shortcuts, a compact header, warm surfaces, burgundy selections, and layouts sized for a 1440 × 940 window. The minimum Mac window size is 1040 × 640.

- Recaps: photo collage and recap list alongside a Worth keeping column; date, conversation, and app filters; existing source review and local generation actions.
- Events: amount and borrowed-item cards above an interactive weekly calendar; access to suggested events and existing agreement editing.
- Messages: searchable conversation list alongside the selected conversation; original source highlighting, media previews, context-menu agreement creation, and explicit send review remain available.
- People: searchable two-column directory and an inline profile with shared agreements, encrypted local notes, and a shortcut to the person's conversation.
- Settings: overview and context/consent panel, plus a separate Mac preferences window with category navigation. Connected Apps, Notifications, Privacy & Data, Devices, Help & Feedback, and Processing & Workspace now share the desktop header and rounded-card layout. Privacy has a focused destination with selected-chat, review, note-visibility, export, and account controls. Nested bridge setup, account, recovery, passphrase, and device-removal screens use the same presentation; existing validation and confirmation steps remain in place.

The iPhone and iPad layouts continue to use the existing views. Normal workspaces never load the sample design data. Debug design previews require a valid isolated `RELAY_TEST_NAMESPACE` plus `RELAY_DESIGN_PREVIEW=1`; optional `RELAY_PREVIEW_APPEARANCE=light|dark` affects only that isolated preview. No personal accounts or messages are used for screenshots.

The SwiftPM Mac resource loader also supports raw sample asset catalogs, preventing blank sample collage images in command-line packaged builds.

Validation: Mac build passed; 43 Swift tests passed and five opt-in integration checks were skipped; the iPad simulator target compiled (with the existing SwiftPM sysroot warning); Xcode project syntax and diff whitespace checks passed. Native visual checks covered all five destinations, recap detail/back navigation, week switching, person selection, privacy navigation, and the separate preferences window. Both light and dark palettes were inspected. The full v5 feature set and physical-device accessibility validation remain outside this UI checkpoint.

Settings follow-up (0.3.3): Mac and iPad simulator builds passed; 48 Swift tests passed and five opt-in live tests were skipped. Native visual checks covered Connected Apps, Notifications, Privacy & Data, Devices, Help, Processing & Workspace, nested bridge/account sheets, back navigation, and the separate preferences window. Light and dark layouts were inspected using an isolated test workspace. The installed real-workspace app was also reopened and its Connected Apps route verified. No live messages were sent or account settings changed during these UI checks.

Conversation picker follow-up (0.3.4): iMessage and bridged chat selection now use the same searchable, bounded list with avatar rows, per-row include/pause actions, and an Included filter. iMessage setup places connection access and local-contact controls beside the picker. The old toggle lists are no longer used on Mac. Both existing local app paths are updated together to avoid launching an older copy.

Validation: Mac and iPad simulator builds passed. 53 tests passed and five opt-in live tests were skipped, including five new contact lookup/search/compatibility tests. Native checks in an isolated workspace covered name search, empty results and clear search, Included filtering, row selection, and the iMessage setup layout. Personal contacts and message content are excluded from source, fixtures, and application archives.
