# iMessage on Mac

Relay for Mac can read newly arriving iMessage text from selected conversations in the local Messages database. Sign in to Messages on the Mac first.

1. Give the updated Relay app Full Disk Access in System Settings → Privacy & Security → Full Disk Access.
2. Quit and reopen Relay. If macOS asks for Keychain access, approve Relay to reopen the existing encrypted workspace.
3. In Relay, open Inbox → Choose Chats → iMessage → Check Access & Refresh Chats.
4. Enable one test conversation. Send a fresh test message after enabling it.
5. Tap Sync Chosen iMessage Chats, or leave Relay active for its 30-second refresh.
6. Create an agreement from the imported text. Its original quote and timestamp are preserved as evidence.

All conversations start off. Enabling a conversation starts at its current latest message; previous history is not imported. Turning it off stops ingestion and hides that conversation from the inbox. Existing source evidence is retained. The database is opened read-only. The reader never modifies the Messages database and does not request Contacts access; participants are identified by their Messages addresses. Confirmed outgoing drafts use the separate native Messages sender described below.

The iMessage connection currently runs on Mac only. It does not stream local Messages conversations to iPad/iPhone or the Matrix server. WhatsApp continues to use its existing Matrix connection. Attachments are shown as unsupported placeholders; tapbacks and edit/control events are not imported as new text. Later message edits/deletions are not yet tracked by this importer.

Verification: the Mac target builds, the iPad simulator target compiles, and the suite passes 27 tests with two unrelated live checks skipped. New iMessage tests cover chat isolation, no-history cursors, rich-text decoding, source evidence/network identity, timestamps, tapback exclusion, and repeated-sync deduplication. Live iMessage verification remains pending.

## Sending from Mac

Type a draft, choose Review Send, verify the existing conversation and message, then choose Send Message. Relay submits that text to the exact existing iMessage chat through the Messages app. It never chooses a recipient by display name or silently falls back to SMS.

On first use, macOS asks whether Relay may control Messages. Approve that prompt yourself. If access was denied, enable Relay → Messages under System Settings → Privacy & Security → Automation. Full Disk Access is still required for reading and resolving the chosen conversation.

A successful handoff is shown as submitted to Messages; recipient delivery must be checked in Messages. The native adapter has no idempotent transaction API. Relay therefore persists a dispatch marker before submission, blocks retry after timeouts or uncertain outcomes, and reconciles against actual self-authored messages. Definitive permission/target errors preserve a retryable draft. Check Messages before discarding an uncertain draft and starting another.

Sending verification: fixed AppleScript compiles against the installed Messages dictionary; tests cover opaque text parameters, exact existing-chat targeting, uncertain-request retry blocking, and one-to-one outbox reconciliation across reload. No external iMessage was sent by automated tests. A user-confirmed live send remains to be checked.


### Conversation names and selection

On Mac, the conversation chooser has a fixed search field above a bounded, scrollable list. Search by conversation title, saved contact name, phone number, or email; use Included to review chosen conversations. Select a row to include or pause it. New conversations remain off until selected.

Choose **Use Contact Names** to request macOS Contacts access. Relay fetches names, phone numbers, and email addresses through the public Contacts framework, builds an in-memory lookup on this Mac, and never uploads the address book. Contacts permission is optional: unknown, ambiguous, or unavailable contacts retain their identifiers. Existing group titles are preserved; unnamed groups use participant names where available. Phone matching uses exact normalized numbers and a US/Canada regional prefix rule rather than arbitrary suffix matching. Chat membership metadata is kept in the existing encrypted, local-only room cache. Display names never replace the stable conversation ID used for sending or change selected chats or cursors.

Names are also used in the Mac conversation sidebar, message headers, sender labels, and People profiles. Saved evidence and agreement snapshots remain unchanged. Contacts changes refresh the in-memory index; locking or signing out clears it. Without Full Disk Access, previously cached chats remain searchable, but refreshing Messages membership metadata still requires that access.
