# Relay identity

The rounded R ends in a speech-bubble tail: a conversation becomes something you can keep. The mark uses the app's existing burgundy and warm cream palette. Its silhouette stays consistent in default, dark, and tinted appearances.

Editable source: [Relay · 08 · Relay Identity](https://www.figma.com/design/10XdD87FnyxKWFoeF0zogy/Relay?node-id=29-252). All SVG, PDF, and 1024-pixel PNG masters in this directory were exported from that Figma page.

- `relay-mark.svg` and `relay-mark.pdf`: transparent, single-color vector master. Tint with the app's semantic accent text color.
- `relay-lockup.svg`: outlined wordmark for fixed artwork. App interfaces use live text beside the mark for accessibility and Dynamic Type.
- `relay-app-icon.svg` and `relay-app-icon.png`: full-bleed default icon, burgundy `#500000` with cream `#FAF7F3`.
- `relay-app-icon-dark.png`: dark `#24191B` with rose `#F2B8BA`.
- `relay-app-icon-tinted.png`: grayscale foundation for iOS tinted icons.
- `Relay.icns`: macOS icon for the SwiftPM packaging script.

The shared RelayKit asset catalog contains the PDF as a preserved template vector. The app target's `Assets.xcassets` contains opaque iOS appearance variants and macOS sizes. Web branding uses the SVG as a `currentColor` mask; Next.js discovers `app/icon.svg` and `app/apple-icon.png` automatically.

Keep the app-icon masters square and unmasked. Platform icon masking is applied by the system. Rounded previews on the Figma brand sheet illustrate the appearance only.

Verified October 25, 2026: web production build, SwiftPM build and macOS packaging, Xcode macOS build, and iOS asset-catalog compilation passed. Browser branding was checked in light and dark appearance, and the native logo was checked in an isolated macOS preview. All 13 native icon entries have the expected dimensions and opaque pixels.
