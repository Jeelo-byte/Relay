# Guided onboarding

Requested October 25, 2026. Use the Apple design skill and Figma generation/use skills. Existing product screens remain the baseline; create a separate setup flow in the existing Relay Figma file.

Design location: [Guided WhatsApp Setup](https://www.figma.com/design/10XdD87FnyxKWFoeF0zogy/Relay?node-id=23-255), page **07 · Guided WhatsApp Setup**.

## Flow

1. **Start with WhatsApp:** explain why the Mac stays running, offer Set Up WhatsApp and a local-only entry point.
2. **Link your account:** show phone instructions beside a private, expiring pairing-code state. Report actual link/error/reconnect status.
3. **Choose conversations:** explicit Include All WhatsApp Chats or individual chat selection. Preserve pauses. Explain gradual discovery without dumping infrastructure details into the flow.
4. **Verify incoming messages:** wait for a real incoming message before claiming delivery. Show sender/time after arrival. Offer troubleshooting and Open Messages.

Use Relay's published buttons, icons, typography and semantic variables. Keep setup optional and resumable from Settings, with Set Up Later on every step. Keep notifications, model downloads, and optional preferences out of the critical path. Provide dynamic type, keyboard focus, VoiceOver actions, light/dark appearances, and compact mobile adaptation.

The four new Figma screens are a design deliverable. Integrating that guided flow into native app startup remains implementation work; the existing account and connection controls continue to work today. Do not claim QR linking is integrated into native onboarding yet.

## Real-data-only requirement

Normal native/web startup must never seed or offer fictional conversations, people, agreements, recaps, or photos. Remove demo launch defaults and sample-workspace buttons. Test fixtures may run only in explicit isolated test contexts. Remove stored fixture records using their explicit demo room IDs; preserve real messages, manual agreements, and mixed-source user records. The app must open to truthful empty states when there is no real data.

## Acceptance

- Fresh launch contains zero sample content; skip opens a usable empty workspace.
- Setup saves progress and resumes without forcing returning users through it again.
- Pairing shows honest expired, disconnected, and failed states.
- All-chat inclusion is explicit, persistent, and supports individual pauses; other services stay separate.
- New texts appear automatically; images render after authenticated loading.
- Create Agreement appears on right-click/long-press, not on every message.
- Website `/docs` explains setup, privacy, chat selection, images, agreements, and troubleshooting with current platform limits.
- A successful build or linked-account badge never substitutes for a real incoming-message check.
