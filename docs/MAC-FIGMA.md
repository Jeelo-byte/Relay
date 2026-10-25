# macOS Figma implementation

The Mac workspace from `codex/mac-figma` is integrated with the current app. iPhone and iPad keep their existing navigation. The original branch was based on `a2a2279`.

Reference: [Relay final product design, macOS page](https://www.figma.com/design/10XdD87FnyxKWFoeF0zogy/Relay?node-id=3-5).

The Mac workspace now uses a persistent 240-point sidebar, selected conversation shortcuts, a compact header, warm surfaces, burgundy selections, and layouts sized for a 1440 × 940 window. The minimum Mac window size is 1040 × 640.

- Recaps: photo collage and recap list alongside a Worth keeping column; date, conversation, and app filters; existing source review and local generation actions.
- Events: amount and borrowed-item cards above an interactive weekly calendar; access to suggested events and existing agreement editing.
- Messages: searchable conversation list alongside the selected conversation; original source highlighting, media previews, context-menu agreement creation, and explicit send review remain available.
- People: searchable two-column directory and an inline profile with shared agreements, encrypted local notes, and a shortcut to the person's conversation.
- Settings: overview and context/consent panel, plus a separate Mac preferences window with category navigation. Existing security, account, devices, notifications, export, and processing screens remain reachable.

The iPhone and iPad layouts continue to use the existing views. Normal workspaces never load the sample design data. Debug design previews require a valid isolated `RELAY_TEST_NAMESPACE` plus `RELAY_DESIGN_PREVIEW=1`; optional `RELAY_PREVIEW_APPEARANCE=light|dark` affects only that isolated preview. No personal accounts or messages are used for screenshots.

The SwiftPM Mac resource loader also supports raw sample asset catalogs, preventing blank sample collage images in command-line packaged builds.

Validation: Mac build passed; 43 Swift tests passed and five opt-in integration checks were skipped; the iPad simulator target compiled (with the existing SwiftPM sysroot warning); Xcode project syntax and diff whitespace checks passed. Native visual checks covered all five destinations, recap detail/back navigation, week switching, person selection, privacy navigation, and the separate preferences window. Both light and dark palettes were inspected. The full v5 feature set and physical-device accessibility validation remain outside this UI checkpoint.
