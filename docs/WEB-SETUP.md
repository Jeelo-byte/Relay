# Local website, sync, and Docker message forwarding

Updated October 25, 2026. This repository is currently a local development setup. Nothing is published by these commands.

## Start the website

From the Relay repository:

```sh
npm install
npm run dev
```

Open **http://localhost:3000** for the public landing page. Unlock the workspace at **http://localhost:3000/workspace**. The setup guide is **http://localhost:3000/docs**. For a production-mode local server, stop development, then run `npm run build && npm start`.

The server needs `DATABASE_URL` and `PRELOGIN_HMAC_SECRET` in the ignored `apps/web/.env.local`. The existing Mac already has them. New installations can copy `.env.example` to that path and fill in the values. Never prefix these secrets with `NEXT_PUBLIC_`. Use the same database and security secret for all instances of this Relay backend. The existing database is initialized; do not reset it. A new database needs `node --env-file=apps/web/.env.local scripts/migrate.mjs` once.

## Sync the same account

1. In the native app, create or unlock a Relay account with the server set to `http://localhost:3000` on this Mac. A workspace started with **Start on This Device** has no signed-in account and does not automatically sync.
2. Unlock the website with that same **Relay handle and passphrase**. The browser derives its keys locally and decrypts the saved agreements and recaps.
3. Sync the native app after saving. The website pulls on unlock, every 30 seconds, on focus, on reconnection, or when you choose the toolbar refresh button.
4. Accept, dismiss, or complete an agreement on the website to save an encrypted update. Sync the native app to receive it.

The browser clears decrypted records and keys on lock/reload. Lock also requests revocation of its Relay API session. Invalid/removed sessions return to sign-in. Failed record verification preserves the pull position for retry. A conflicting edit refreshes the server version; review it before applying your change again. Browser edits need a working connection; there is no durable offline web outbox yet.

Private person notes and iMessage history do not currently sync to the website. Full conversation text follows the separate message-server connection below.

## How Docker forwarding works

```text
WhatsApp on your phone ↔ linked-device session in mautrix-whatsapp
                                      ↕
                          Synapse Matrix homeserver
                            ↙                   ↘
                     Relay native          Relay web browser
                     chosen chats          chosen chats
                            ↘                   ↙
                      Relay API → encrypted records in Neon
```

Docker runs the bridge and Synapse. The WhatsApp bridge receives messages through its linked-device session and turns them into Matrix room events. Synapse stores the room events and photos on the bridge host. Relay reads only included chats from that message server. A confirmed web reply goes back through Synapse and the bridge to the network. Docker itself does not forward messages into Neon: the Relay account API stores encrypted derived records and source excerpts separately.

WhatsApp's network encryption terminates at the bridge. This setup's Matrix bridge rooms are unencrypted inside the local message plane; Relay web refuses encrypted Matrix rooms because it does not implement Matrix end-to-end encryption. The browser connects directly to Synapse, without proxying Matrix passwords, tokens, or full chat text through the Relay API.

## Start the existing Mac message stack

Start Docker Desktop, then from this repository:

```sh
npm run messages:status
npm run messages:start
```

The start command runs **Synapse, Element, and WhatsApp** using `infra/matrix/compose.yml`. It reuses the existing ignored `infra/matrix/private/` configuration and data. It does not link an account or enable chats automatically. The launcher honors Docker's active context and any explicit `DOCKER_HOST`; it no longer assumes a Colima socket.

Useful checks:

```sh
bash scripts/live-docker.sh ps
bash scripts/live-docker.sh logs --tail 50 synapse whatsapp
curl http://127.0.0.1:8008/_matrix/client/versions
curl http://localhost:3000/api/v1/health
```

The first curl checks the message server; the second checks the Relay API/database. Bridge logs can contain private information: inspect them locally. Runtime configuration, credentials, media, and bridge databases stay under ignored `infra/matrix/private/`; back it up privately. Do not delete that directory to troubleshoot. Stop services without deleting their data with `bash scripts/live-docker.sh stop synapse element whatsapp`.

The separate `compose.live.yml` describes an optional PostgreSQL stack. It is not the running Mac stack and is not needed for this setup. Selecting it with `RELAY_MATRIX_STACK=live` requires its own initialized PostgreSQL data, `private/runtime.env`, and matching homeserver/bridge configurations; it is not an automatic migration from the existing SQLite stack.

## Pair WhatsApp and connect the website

1. Open **http://127.0.0.1:8088** (Element) on the Mac and sign into the existing Matrix account. These are **Matrix credentials**, separate from your Relay handle/passphrase. The current development account is stored in `infra/matrix/private/relay-account.json`; keep its password private.
2. Open your existing WhatsApp bridge management conversation. If needed, request `login qr`. On the phone choose **WhatsApp → Settings → Linked Devices → Link a Device** and scan the QR. If already linked, reuse it. Do not repeatedly relink.
3. In Relay's website, unlock your Relay account, then open **Messages → Live Chats**. Enter `http://127.0.0.1:8008` and the Matrix username/password. Choose **Connect Messages**.
4. Select a conversation and turn on **Include**. All chats start off in each browser session. Inclusion is independent from the native app's choices. Only joined rooms appear; accept wanted invitations in Element. The bridge's `sync groups` command can discover existing WhatsApp groups.
5. New messages refresh about every three seconds while the page is running. Search covers loaded text; **Load Earlier Messages** fetches older Matrix events. Photos use authenticated downloads with a 20 MB limit. **Saved Sources** still shows excerpts synced with agreements.
6. Compose a reply, choose **Review Reply**, verify the destination/text, then **Confirm Send**. Retrying a failed confirmation reuses its transaction ID to avoid duplicates. Do not assume delivery to WhatsApp merely because Synapse accepted the event; check the network when testing real sending.
7. **Disconnect Messages** clears the message connection. **Lock Relay** clears both account and message views and requests logout. Navigation within Relay preserves the live connection; reloading requires reconnecting.

The Mac and Docker must stay awake and online for the current bridge to receive messages. Browser refresh runs only while the page is running; it is not a background forwarding service. Other bridge containers may run without having linked third-party accounts. WhatsApp is the currently verified incoming network.

## A new machine

The compose file alone is not a complete installer: it mounts private configuration and registered appservices from this Mac. For a new host, generate Synapse configuration, create a Matrix user, generate the WhatsApp bridge configuration and appservice registration, register that appservice in Synapse, and restart the homeserver before linking. Use the pinned images in the compose file and follow [Mautrix's Docker setup](https://docs.mau.fi/bridges/general/docker-setup.html) and [WhatsApp instructions](https://docs.mau.fi/bridges/go/whatsapp/). Use Docker service names (`http://synapse:8008`, `http://whatsapp:29318`) inside the containers; `localhost` there points to that container.

## Phone, another computer, or eventual online hosting

`localhost` refers to the device opening the address. A phone cannot reach this Mac using `localhost:3000` or `127.0.0.1:8008`. Provide trusted HTTPS addresses for both the Relay API and Matrix homeserver, for example through your existing private network/reverse proxy. The native account server must point to the reachable Relay API address, and the browser's message connection must point to the reachable Matrix address.

Do not publish raw port 8008. Follow [Synapse's reverse-proxy instructions](https://element-hq.github.io/synapse/latest/reverse_proxy.html), preserve its CORS support, and keep admin/appservice access private. An HTTPS website requires an HTTPS message server. Hosting the Next.js site does not host Docker; an always-on message host still needs persistent bridge sessions, storage, private networking, and backups. No remote hosting or cross-device HTTPS route has been deployed by this change.

For the local demo, [Mac hosting](HOSTING.md) starts the website on 127.0.0.1:3100 and a loopback gateway on 127.0.0.1:3400. Tailscale is optional and not part of the current demo.
