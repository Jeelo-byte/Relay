# iMessage on Mac

Relay for Mac can read newly arriving iMessage text from selected conversations in the local Messages database. Sign in to Messages on the Mac first.

1. Give the updated Relay app Full Disk Access in System Settings → Privacy & Security → Full Disk Access.
2. Quit and reopen Relay. If macOS asks for Keychain access, approve Relay to reopen the existing encrypted workspace.
3. In Relay, open Inbox → Choose Chats → iMessage → Check Access & Refresh Chats.
4. Enable one test conversation. Send a fresh test message after enabling it.
5. Tap Sync Chosen iMessage Chats, or leave Relay active for its 30-second refresh.
6. Create an agreement from the imported text. Its original quote and timestamp are preserved as evidence.

All conversations start off. Enabling a conversation starts at its current latest message; previous history is not imported. Turning it off stops ingestion and hides that conversation from the inbox. Existing source evidence is retained. The database is opened read-only. This integration does not send messages or request Contacts access; participants are identified by the addresses in Messages.

The iMessage reader currently runs on Mac only. It does not stream local Messages conversations to iPad/iPhone or the Matrix server. WhatsApp continues to use its existing Matrix connection. Attachments are shown as unsupported placeholders; tapbacks and edit/control events are not imported as new text. Later message edits/deletions are not yet tracked by this importer.

Verification: the Mac target builds, the iPad simulator target compiles, and the suite passes 27 tests with two unrelated live checks skipped. New iMessage tests cover chat isolation, no-history cursors, rich-text decoding, source evidence/network identity, timestamps, tapback exclusion, and repeated-sync deduplication. Live iMessage verification remains pending.
