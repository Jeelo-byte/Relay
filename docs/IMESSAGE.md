# iMessage and contacts

Relay on Mac reads chosen conversations from the local Messages database and sends reviewed text replies through Apple Messages. Sign in to Messages on the Mac first. The Messages database remains read-only. Sending uses Messages’ AppleScript `send` command, with the chat id and text passed as Apple event parameters rather than inserted into the script.

## Connect and read

1. Give Relay Full Disk Access in System Settings → Privacy & Security → Full Disk Access.
2. Quit and reopen the updated Relay app after changing access.
3. Open Settings → Connections → iMessage and check access / refresh chats.
4. Choose the conversations Relay can include. Chats start off; enabling one starts at its current latest message.
5. To include history, choose **Import Recent Messages** to import up to 100 recent messages per selected chat. Otherwise only new arrivals are imported.
6. Use **Sync Chosen iMessage Chats**, or keep Relay active for its 30-second refresh.

Pausing a conversation stops ingestion and hides it from Messages in Relay. Existing agreement source evidence is retained. Attachments appear as unsupported placeholders; tapbacks and control events are excluded. Later edits/deletions are not tracked yet.

## Send a reply

Open a chosen conversation in Relay’s Messages view, type a reply, choose **Review Send**, review the destination and text, then choose **Send Message**. On the first attempt macOS asks to allow Relay to control Messages. Allow it, or enable Relay → Messages under System Settings → Privacy & Security → Automation.

Relay targets the existing iMessage chat GUID, including group chats, and never guesses recipients or falls back to SMS. It records the pending request in its encrypted outbox before asking Messages to send. Success requires matching outgoing text in the same chat after the saved cursor, with no recorded error and `is_sent` set when available. This confirms the outgoing record; check Messages for delivery/read receipts.

Messages has no transaction-key API. If sending times out, Relay preserves the draft and **Check Send Status** looks for the existing outgoing message without sending again, including after an app restart. Check Apple Messages before discarding that draft and intentionally starting a new send. Older outbox records created before this feature have no dispatch cursor; only new attempts use this mechanism.

Use the app bundle built by Xcode or `bash scripts/package-mac.sh`. The package and Xcode target include Contacts and Apple Events usage descriptions and Mac Automation entitlements. An unsigned Swift package executable is not the recommended way to exercise macOS privacy permissions. Changing ad-hoc signatures may require granting access again.

### Conversation names and selection

On Mac, the conversation chooser has a fixed search field above a bounded, scrollable list. Search by conversation title, saved contact name, phone number, or email; use Included to review chosen conversations. Select a row to include or pause it. New conversations remain off until selected. The optional Import Recent Messages action includes up to 100 earlier messages from each chosen chat.

Choose **Use Contact Names** to request macOS Contacts access. Relay fetches names, phone numbers, and email addresses through the public Contacts framework, builds an in-memory lookup on this Mac, and never uploads the address book. Contacts permission is optional: unknown, ambiguous, or unavailable contacts retain their identifiers. Existing group titles are preserved; unnamed groups use participant names where available. Automatic display-name lookup uses normalized numbers and a US/Canada regional prefix rule rather than arbitrary suffix matching. Identity linking in People keeps the exact-address rules below; explicit contact names and unlink decisions take priority over automatic display lookup. Chat membership metadata is kept in the existing encrypted, local-only room cache. Display names never replace the stable conversation ID used for sending or change selected chats or cursors.

Names are also used in the Mac conversation sidebar, message headers, sender labels, and People profiles. Saved evidence and agreement snapshots remain unchanged. Contacts changes refresh the in-memory index; locking or signing out clears it. Without Full Disk Access, previously cached chats remain searchable, but refreshing Messages membership metadata still requires that access.

## Import contacts and link profiles

In **People**, choose **Import Contacts → Import Device Contacts**, **Import vCard File**, or **Add Person**. Device import requests Contacts permission only when selected and imports the contacts macOS/iOS makes accessible. vCard files can come from Apple Contacts, Google Contacts, Outlook, or another address book that exports `.vcf`. Importing does not modify the source address book.

Unique exact email addresses and phone numbers (ignoring formatting, retaining country codes) match iMessage participants and recognized WhatsApp phone identities. Names, number suffixes, and arbitrary usernames do not trigger matches. Shared addresses on multiple contact cards stay ambiguous. Phone numbers without a country code are not expanded using a guessed region.

Open a person and choose **Edit Details & Links** to select platform profiles, unlink automatic matches, or add an exact platform identity manually. Unlinked profiles offer **Link to a Contact** to choose an existing person or create one. Moving a manually linked identity to another person removes its previous manual link. An explicit unlink survives reimport. Reimporting device contacts refreshes addresses while preserving your edited name and links.

Linked profiles share one People entry and agreement list. Original sender IDs, source quotes, and agreement parties remain intact. Imported names appear on conversation messages and unnamed direct iMessage chats. Contacts, linking decisions, and private notes are encrypted locally and excluded from cloud record sync. Sign-out clears contacts from Relay. Contacts and Mac-local iMessage conversations do not yet sync between devices or to the web. Reading/sending the local Messages database is Mac-only; contact management also works on iPhone/iPad.

## Verification

Automated fixtures exercise selected-chat isolation, recent-history import, participant discovery, exact group/direct routing, actual-event deduplication, uncertain-send reconciliation across restart, locked/paused send rejection, Apple event parameter handling, contact matching/ambiguity, vCard import, encrypted persistence, and link transfer/unlink behavior. Live delivery requires the user’s macOS privacy grants and a chosen test recipient; no real messages are sent by the automated tests.
