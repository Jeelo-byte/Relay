import Link from "next/link";

export const metadata = {
  title: "Relay — Local messaging workspace",
  description:
    "A Mac app and local website for chosen iMessage, WhatsApp, and Matrix chats, with encrypted records and offline unlock after an online sign-in.",
};

const working = [
  {
    badge: "Agreements",
    title: "You keep the promise and the message it came from.",
    body: "Create, accept, dismiss, and complete agreements yourself. Money stays in exact minor units. The source quote stays attached. An agreement here is a shared understanding, not a legal contract.",
  },
  {
    badge: "Encrypted records",
    title: "Ciphertext on the device. Keys in this browser’s memory.",
    body: "The Mac app encrypts its local records. This website derives keys from your passphrase and decrypts saved agreements and recaps for the same account. Lock or reload and that decrypted copy is cleared. Person notes and full iMessage history stay off website sync.",
  },
  {
    badge: "Recaps and Events",
    title: "A day of chosen chats, and the week’s open items.",
    body: "Recaps group chosen conversations and keep the quote. Events holds money, borrowed things, and the week. The next occurrence of a repeating item waits until you accept it.",
  },
  {
    badge: "WhatsApp on this Mac",
    title: "Four setup steps, then a real incoming message.",
    body: "The Mac app walks through Get started, Link WhatsApp, Choose chats, and Check delivery. Incoming text in a chosen chat and photo previews have been checked on this Mac. A reply is reviewed before it is sent. Confirm delivery in WhatsApp.",
  },
  {
    badge: "Live chats on this website",
    title: "Matrix on localhost, chats off until you include them.",
    body: "After unlock, Messages → Live Chats connects to the Matrix server on this Mac. Include the rooms you want, then read text and photos and search what has already loaded. A reply waits for Confirm Send. Lock, reload, or leaving the page drops that connection.",
  },
  {
    badge: "iMessage on the Mac",
    title: "Full Disk Access and Automation come first.",
    body: "Relay can read chats you choose and send a reviewed text reply through Apple Messages after those two macOS permissions are granted. Without them, reading and sending do not run. iMessage stays on the Mac. This website, iPhone, and iPad do not receive those chats yet.",
  },
  {
    badge: "Offline unlock",
    title: "Sign in online once. The same device can unlock later.",
    body: "After an online sign-in, that device can unlock with the passphrase while offline. Rotating the encryption data key, and merging two devices’ edits field by field, are still unfinished.",
  },
];

export default function LandingPage() {
  return (
    <div className="setup-guide landing">
      <header className="guide-header">
        <Link className="guide-brand" href="/">
          <span className="relay-logo" aria-hidden="true" />
          Relay
        </Link>
        <span>Local workspace</span>
        <nav className="landing-nav" aria-label="Site">
          <Link href="/docs">Setup guide</Link>
          <Link href="/workspace">Open workspace</Link>
        </nav>
      </header>
      <div className="landing-layout">
        <section className="landing-hero" aria-labelledby="landing-title">
          <span className="source-badge">Mac app · Local website</span>
          <h1 id="landing-title">
            Every promise.
            <br />
            Kept with the chat it came from.
          </h1>
          <p className="landing-lede">
            Relay is a local-first messaging workspace. The Mac app and this
            website keep chosen iMessage, WhatsApp, and Matrix conversations
            next to the agreements and recaps you save from them. Records are
            encrypted on the device. Sign in online once, and that device can
            unlock offline afterward.
          </p>
          <h2>Who it is for</h2>
          <p>
            Someone already talking in those apps, who wants one place on their
            Mac for who promised what, what is still open, and which message it
            came from. Create the account in the Mac app. This website unlocks
            the same handle. The repository does not publish the site to the
            public internet.
          </p>
          <div className="landing-actions">
            <Link className="landing-cta" href="/workspace">
              Open the workspace
            </Link>
            <Link className="guide-start" href="/docs">
              Read the setup guide
            </Link>
          </div>
        </section>
        <section className="landing-sheet" aria-labelledby="works-now">
          <p className="landing-kicker">What works now</p>
          <h2 id="works-now">Checked on this Mac. Unfinished work stays labeled.</h2>
          <div className="landing-ledger">
            {working.map((item) => (
              <article key={item.badge} className="landing-entry">
                <span className="source-badge">{item.badge}</span>
                <h3>{item.title}</h3>
                <p>{item.body}</p>
              </article>
            ))}
          </div>
        </section>
      </div>
      <section className="landing-steps" aria-labelledby="get-in">
        <h2 id="get-in">How you get in</h2>
        <ol>
          <li>
            In the Mac app, create or unlock a Relay account. Point the account
            server at this website when the two should sync. A workspace started
            only on the device does not sync by itself.
          </li>
          <li>
            <Link href="/workspace">Open the workspace</Link> and unlock with
            the same handle and passphrase. Your keys stay in this browser’s
            memory until you lock or reload.
          </li>
          <li>
            <Link href="/docs">Read the setup guide</Link> for the local
            website, Docker message forwarding, and WhatsApp. Guided setup for
            every other messaging service is not in the app yet.
          </li>
        </ol>
      </section>
      <section className="landing-limits" aria-labelledby="still-ahead">
        <h2 id="still-ahead">What still needs setup</h2>
        <p>
          iMessage sending on the Mac waits on Full Disk Access and Automation.
          The last checkpoint did not send a real iMessage. Those chats remain
          on the Mac.
        </p>
        <p>
          Tailscale HTTPS for a phone, an always-on host, data-key rotation,
          and field-by-field conflict merge are later work. Other bridge
          processes can be running on this Mac without a linked account.
          WhatsApp is the service with the four-step guide today.
        </p>
      </section>
      <footer className="guide-footer">
        <span>A shared-understanding view, not a legal contract.</span>
        <Link href="/workspace">Unlock agreements</Link>
      </footer>
    </div>
  );
}
