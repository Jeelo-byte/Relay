# Messaging onboarding

Relay's first-launch setup asks which apps to connect: WhatsApp, Telegram,
Discord, Signal, Slack, Google Messages, Messenger, Instagram, and iMessage. Reopen it from Settings → Set Up Messaging
Apps. Existing WhatsApp pairing and chat inclusion settings are retained.

## Fresh Mac: prepare the message server

1. Install Docker Desktop. Open Relay and select your apps.
2. For Telegram, enter the API ID and hash from [my.telegram.org](https://my.telegram.org).
   Relay saves them only in the private Telegram bridge configuration. Then choose
   **Prepare Message Server**. Relay opens Docker if needed, downloads
   pinned images, generates private configuration and bridge registrations, starts
   Synapse and only the selected bridges, and saves the Matrix session in Keychain.
3. Open each app in the setup list to link its account and select conversations.
4. Receive a new text in an included chat, then open that conversation in Relay,
   type a reply, choose **Review Send**, and confirm it. Check the reply in the
   original messaging app.

No host Python, pip, or Node installation is required. Setup uses the Python
runtime in the pinned Synapse container. Mac host data lives in
`~/Library/Application Support/Relay/MessageHost`; it includes private message
databases and account credentials. Its `setup.log` contains Docker setup diagnostics.
Never publish the host directory or its private files.

The Matrix and Element ports bind to loopback, by default 8008 and 8088. Keep the
Mac and Docker running. Other devices require an existing HTTPS message-server
address; they cannot create the Mac host themselves. iMessage remains Mac-only.

## Existing message server / working WhatsApp

If a Matrix session is already saved, onboarding uses that server and does not
replace it with a new account. Choose **Server Settings** to change the connection.
The selected bridges must be installed on that existing host. A new local host
cannot inherit a WhatsApp device session from another host automatically.

For maintainers using this repository's existing `infra/matrix/private` local stack:

```sh
# In the existing Python environment with PyYAML installed, choose the bridges you need:
python scripts/prepare-bridges.py --services telegram discord signal slack gmessages meta instagram
bash scripts/live-docker.sh --profile bridges up -d telegram discord signal slack gmessages meta instagram
bash scripts/live-docker.sh restart synapse
```

This adds selected registrations without dropping other registrations or replacing
an existing bridge database. `meta` is the Messenger bridge on this existing
stack; new native hosts use the service name `messenger`. Telegram requires your
API ID and hash in its private bridge configuration before it starts. Instagram
has its own bot and Matrix namespace. Account login is still required.
The optional PostgreSQL live stack requires its existing deployment workflow.

## Link each account

- **WhatsApp:** the existing in-app QR flow is retained. Scan from Linked Devices.
- **Discord:** choose Start Account Linking, scan the QR in Discord's mobile app,
  and approve login. If Discord requires an unsupported CAPTCHA, follow the linked
  bridge documentation for its alternative account-linking methods.
- **Google Messages:** use the supported Google account flow. In a private browser
  window, open the link shown in Relay, copy the `/web/config` request as cURL from
  developer tools, and submit it when the bridge asks. Approve the matching emoji
  on the Android phone and keep that phone online. QR login is no longer supported
  by Google. A private Firefox window avoids device-bound-session restrictions.
- **Instagram:** follow the in-app instructions to obtain authenticated cookies
  from a private browser login. Submit the requested JSON or cURL text to the bridge.
  Complete any account verification in Instagram.
- **Telegram:** enter your API ID and hash during host setup, then choose Start
  Account Linking. In Telegram on your phone, open Settings → Devices → Link
  Desktop Device and scan the code. Send your two-factor password if prompted.
- **Signal:** choose Start Account Linking, then use Signal → Settings → Linked
  Devices → Link New Device to scan the code. Without history transfer, chats may
  appear only when new messages arrive.
- **Slack:** choose Open Slack Setup. In a private browser window, obtain the
  workspace's `xoxc` token and `xoxd` `d` cookie. Enter
  `login token <token> <cookie>` in the private setup field. The bridge also
  supports `login app` for a workspace app.
- **Messenger:** choose Start Account Linking, sign in at messenger.com in a
  private browser window, and send the requested authenticated cURL request or
  cookies to the private setup room. Complete any account check in Messenger.
- **iMessage:** sign in to Messages on the Mac, enable Full Disk Access for Relay,
  and restart Relay if macOS requires it. Refresh conversations and include the
  ones you want. The first confirmed send requires Automation access to Messages.
  Check delivery in Apple Messages; uncertain native sends are reconciled rather
  than automatically sent again.

Credentials entered during linking go to the service bot in a verified private
Matrix setup room. They are never executed as shell commands. The message server
and bridge can access them; setup rooms are excluded from Relay's conversation
list and ingestion. Pairing images and typed credentials clear when the view loses
focus or the workspace locks. Starting linking again cancels an unfinished login.

## Chat selection and two-way transport

Selecting a service permits discovery of invitations from that exact local bridge
bot. Joining a portal does not include its messages automatically. New non-WhatsApp
chats remain off until selected. Existing WhatsApp Include All and per-chat pauses
keep their previous behavior. The common Matrix sender and encrypted local outbox
handle replies for all bridged services with stable transaction IDs.

Google Messages can represent texts sent from the linked phone as bridge ghost
events. On the Mac message host, Relay reads the bridge's own participant IDs
and saves the corresponding Matrix sender IDs in that Matrix account's private
account data. Relay uses the mapping on Mac and iPhone to label those texts as
yours, including previously cached messages. The mapping contains sender IDs,
not message contents.

A successful Matrix submission means the local server accepted the text; the
original service determines delivery. Receive a new incoming text and verify a
confirmed reply in each original app before considering the account fully tested.

## CLI fresh-host setup and verification

```sh
bash scripts/setup-messages.sh instagram gmessages discord whatsapp
```

The CLI saves its session under the ignored `infra/matrix/onboarding` directory.
Use `RELAY_MESSAGE_HOST` to choose a different private host directory. Test ports
can be changed with `RELAY_MATRIX_PORT` and `RELAY_ELEMENT_PORT`, without stopping
another server or SSH forwarding connection.

Opt-in tests can use a disposable local host:

```sh
RELAY_VERIFY_BRIDGES_SESSION="$PWD/infra/matrix/onboarding/session.json" \
  swift test --filter BridgeLiveTests
```

These verify real local bridge-bot login responses, exclusion of setup rooms,
Matrix text submission and sync, and idempotent retries. They send no text to a
remote contact and do not prove delivery through an unlinked external account.
To exercise Relay's persisted outbox path against one private disposable room,
run `swift test --filter BridgeLiveTests/testRelayStoreOutgoingPathInDisposableRoom`
with the same session variable. The test leaves the room after verifying its
event and stable retry; it does not invite a bridge or remote contact.
Other native tests cover setup persistence, consent, private-room checks,
stale/wrong-bot responses, and pairing-code expiry.

References: [Telegram authentication](https://docs.mau.fi/bridges/go/telegram/authentication.html),
[Signal authentication](https://docs.mau.fi/bridges/go/signal/authentication.html),
[Slack authentication](https://docs.mau.fi/bridges/go/slack/authentication.html),
[Messenger authentication](https://docs.mau.fi/bridges/go/meta/authentication.html),
[Discord authentication](https://docs.mau.fi/bridges/go/discord/authentication.html),
[Google Messages authentication](https://docs.mau.fi/bridges/go/gmessages/authentication.html),
[Instagram authentication](https://docs.mau.fi/bridges/go/meta/authentication.html).
