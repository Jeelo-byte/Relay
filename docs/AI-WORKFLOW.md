# Automatic conversation AI

Implemented after integrating the desktop connection and Settings branch on October 25, 2026.

## Product behavior

Messages remains an ordinary messaging interface. Reading, composing, viewing images, and reviewing a send do not depend on AI.

Each included chat has its own conversation boundary: a gap of at least five minutes between messages. Text and media activity postpone processing. While Relay is running and unlocked, a ten-second scheduler checks for closed conversations. A later conversation in the same room gets its own recap. A continuation or edit inside an existing segment changes its fingerprint and updates the same recap identity.

The default is automatic processing. Settings → Processing & Workspace offers an Automatic AI toggle and status. A previously downloaded Gemma model loads automatically; first-time installation retains the explicit multi-GB download action. Missing models do not block messaging. iPhone/iPad processing runs while the app is active; the running Mac can process while its window is unfocused. This is not an OS background-execution or always-on server guarantee.

## AI outputs

- **Recaps:** meaningful conversation summaries with exact source quotes. Ordinary small talk can produce no card. A short exchange produces a card only when it yields a commitment or a detail selected as worth keeping; otherwise the minimum is six messages plus a meaningful model result.
- **Worth keeping:** exact cited excerpts about decisions, preferences, plans, or obligations. They are context, not verified biographical facts.
- **People:** excerpts attach to their actual speaker and respect manually linked identities. Group membership never attaches everyone else's statements to a person. AI never overwrites private notes or merges contacts.
- **Events:** new commitments remain suggestions. Updates, completion, and cancellation remain changes to review; AI never silently changes an accepted agreement.
- **Replies:** opening a conversation automatically generates editable, source-backed suggestions in response to incoming messages. It does not wait for the five-minute recap timer. Choosing a suggestion fills an empty composer; it never overwrites a draft or sends a message.
- **Search:** native chat search combines exact matches with on-device sentence and content-word embeddings. Quoted searches retain exact matching. Indexing follows included chats, edits, and deletions. Unsupported embedding languages fall back to word matching. Search returns original messages rather than an uncited generated answer.

The web displays synced automatic recaps, worth-keeping excerpts, and People context. The browser does not run Gemma or the native semantic-search model. A running Apple client must generate and sync those derived records. Contacts and handwritten person notes remain device-local under the existing sync contract.

## Long conversations and validation

Conversation segments are processed in overlapping windows of at most 30 messages, rather than silently considering only the final 35. Pairwise consolidation combines all chunk summaries and revalidates citations against original messages. Individual prompt message text retains the existing 1,500-character bound. Summaries are at most 600 characters; each summary and worth-keeping item has exact supporting excerpts. Citation validation does not prove that every generated sentence is logically entailed, so factual quality still needs evaluation.

The encrypted local checkpoint includes successful empty results, avoiding repeated processing after relaunch. Failed validation gets one repair attempt and a one-minute retry delay. Account changes, locking, opt-out, AI pause, and changed conversations invalidate in-flight work. Existing account processing leases coordinate online devices; ownership is checked again before publishing results. New proposal identities are stable across devices for the same source and parties. Full offline multi-device conflict reconciliation remains separate work.

Recaps and excerpts use the existing authenticated encrypted record schema, with optional fields for compatibility. Embeddings and search text remain in memory. No AI output sends external messages, accepts commitments, edits address books, or modifies personal notes.

## Verification and remaining acceptance

Automated coverage is in `ConversationAITests.swift` and `apps/web/lib/recap-context.test.mjs`, alongside the existing extraction, recurrence, search, messaging, and crypto suites. The opt-in `RELAY_VERIFY_MODEL=1` case runs automatic recap generation, payment extraction, and contextual replies using the actual cached model.

Before release, evaluate a labeled corpus with:

1. Short chatter, substantive exchanges, and busy 35/100/300-message groups; important facts near the beginning, middle, and end.
2. Multiple topics, midnight boundaries, late arrivals, edits, deleted sources, duplicate deliveries, and long individual posts.
3. Accepted and unaccepted plans, changed deadlines, cancellations, partial payments, jokes, sarcasm, and embedded instructions.
4. Useful preferences versus someone describing another person; identity links and ambiguous names.
5. Search paraphrases with plausible distractors, multiple languages, missing embeddings, and excluded chats.
6. Reply relevance and tone, invented promises or availability, source validation, and draft preservation.
7. Model loading/failure, interrupted processing, restart recovery, online leases, offline behavior, account switches, and permission withdrawal.
8. A real incoming chat → automatic recap → cited source → reviewed Event → People context → account sync → second device/browser walkthrough.

Record factual errors, missed important details, false positives, irrelevant search results, duplicate records, and end-to-end latency separately. Passing a small real-model fixture is not a claim that all conversations or live integrations have been verified.

Embedding API reference: [Apple Natural Language — NLEmbedding](https://developer.apple.com/documentation/naturallanguage/nlembedding).

## October 25 verification checkpoint

- Isolated Swift run: 71 RelayKit tests and one app test executed; 66 passed, six opt-in cases skipped, zero failures. This includes regression coverage for preserving accepted/dismissed records when an edited source is reprocessed.
- Isolated JavaScript run: 15 passed, two live-service cases skipped, zero failures. The production web build passed without depending on the concurrent device-pairing work.
- Actual cached Gemma evaluation: the new automatic workflow test and the existing extraction/recap integration test both passed, in 49.7 seconds together. The new test covers cited People context, payment extraction, contextual replies without sending, and a 40-message conversation whose early vegetarian preference and final Green Table decision both survive consolidation.
- iPhone Simulator: chat search/source navigation, recap photos/sources, and explicit confirmation before a sample send all passed. Result bundle: `artifacts/ai-messaging-ui.xcresult` in the original checkout. Fixtures stayed isolated; no real message was sent.

These results establish the first automatic-AI checkpoint. Real-network cross-device AI/account sync, the broader labeled quality corpus, unsupported languages, physical-device resource behavior, and the full accessibility pass remain open.
