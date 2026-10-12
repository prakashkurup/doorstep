# Doorstep

**Every package, one glance.** A macOS menu bar app that turns the shipping emails in your Gmail
into a calm, live list of what's arriving, what to return, and what you've spent. Everything is
read on your Mac; nothing goes to a server but Gmail and (optionally) the carriers themselves.

<p align="center">
  <img src="docs/images/hero.png" alt="Doorstep: the Arriving list, an order with live carrier scans, and monthly spending" width="900">
</p>

<sub>Screenshots use the app's built-in sample orders.</sub>

## A quick tour

<table>
<tr>
<td width="50%" valign="top">

### Arriving
Packages grouped by **Today**, **Tomorrow**, **Running late** and **Later**, each with a colored
status and a 4-step progress bar. The package that's out for delivery gets a card with its
delivery window and a little truck on the last stretch. A **week strip** shows which days have
deliveries (click a day to filter), and a one-line reminder appears when a return window is about
to close.

</td>
<td width="50%" valign="top">
<img src="docs/images/arriving.png" alt="Arriving tab" width="380">
</td>
</tr>
<tr>
<td width="50%" valign="top">
<img src="docs/images/order-detail.png" alt="Order detail with live carrier scans" width="380">
</td>
<td width="50%" valign="top">

### Every order, in detail
The current status in plain words ("Today, 10:30 AM – 2:30 PM"), the full timeline, order
number, total and tracking number with one-click copy. With **live carrier tracking** on, the
timeline becomes every scan from UPS, USPS, FedEx or DHL, with the city it happened in and a small
map of the last scan.

</td>
</tr>
<tr>
<td width="50%" valign="top">

### Returns
Return deadlines for delivered orders (stated in the email, or the store's usual window, marked
*est.*), returns in progress (started → sent back → received → refunded), and refunds, including
the small ones for unavailable grocery items. You get a notification 3 days before a window closes.

</td>
<td width="50%" valign="top">
<img src="docs/images/returns.png" alt="Returns tab" width="380">
</td>
</tr>
<tr>
<td width="50%" valign="top">
<img src="docs/images/spending.png" alt="Monthly spending by store" width="380">
</td>
<td width="50%" valign="top">

### Spending
What you spent each month, by store, from the order totals in your email, plus the change from
last month and refunds. Stores whose emails carry no price (a carrier's shipping notice only) are
named, so a low month never looks mysterious.

</td>
</tr>
</table>

### In the menu bar

<p align="center">
  <img src="docs/images/menu-bar.png" alt="Menu bar states: idle, packages in transit, arriving today with a delay warning" width="660">
</p>

The icon stays quiet when nothing's coming, counts packages in transit, switches to
**"1 today"** (or the carrier's delivery window) on delivery day, and adds a warning mark when
something is delayed. It hops when a package goes out for delivery and wiggles when it arrives.

### Also

- **Signature required** badge when someone needs to be home.
- **Product photos** from the email; otherwise a category icon, the store's logo or the carrier's.
- **Paste to track:** copy any UPS/USPS/FedEx/DHL number, open the panel, press ⌘V.
- **Right-click any order:** copy tracking number, track, open the email, mark as received, hide.
- **Searchable history** of everything delivered in the last 60 days.
- **Notifications** only when it matters: out for delivery, delivered, delayed, return window closing.
- Liquid Glass controls, light and dark mode, and Reduce Motion respected.

| Shortcut | Action |
| --- | --- |
| ⌥⌘D | Open or close Doorstep from anywhere |
| ⌘1 / ⌘2 / ⌘3 | Arriving / Returns / Delivered |
| ↑ ↓ then ↩ | Move through orders and open one; Esc goes back |
| ⌘R | Refresh |
| ⌘V | Track a copied tracking number |

### Privacy

- **Gmail access is read-only.** Doorstep can't send, delete or change email.
- **Order details are extracted on your Mac,** using schema.org markup, text patterns and Apple's
  on-device Foundation Models. Emails are never uploaded anywhere.
- **Live tracking is optional,** and sends only tracking numbers, to the carriers you connect.
- Credentials live in the macOS Keychain; cached orders live in `~/Library/Application Support/Doorstep`.

## Build and run

Requires macOS 26+ and the Xcode Command Line Tools (full Xcode not needed).

```sh
scripts/build-app.sh            # builds build/Doorstep.app
scripts/build-app.sh --install  # also copies to ~/Applications and launches it
```

Without Gmail connected, choose **Preview with sample orders** to try the UI.

**Stop Keychain prompts after rebuilds (one-time):** `scripts/make-signing-cert.sh` creates a local
"Doorstep Local Signing" identity in your login keychain; `build-app.sh` uses it automatically so
every build keeps the same signature. Click **Always Allow** once after switching.

## Connect Gmail (one-time, ~5 minutes)

Doorstep needs its own Google OAuth client. It's free and only you will use it.

1. Open <https://console.cloud.google.com/projectcreate> and create a project (e.g. "Doorstep").
2. Enable the Gmail API: <https://console.cloud.google.com/apis/library/gmail.googleapis.com> → **Enable**.
3. Configure the consent screen: <https://console.cloud.google.com/auth/branding>
   - App name "Doorstep", your email for support/developer contact.
   - Audience: **External**. Add your Gmail address under **Test users**.
4. Create the client: <https://console.cloud.google.com/auth/clients> → **Create client** →
   type **Desktop app** → name it → **Create** → **Download JSON**.
5. Move the downloaded file to:
   ```
   ~/Library/Application Support/Doorstep/client_secret.json
   ```
   (The app's **Show folder** button opens this folder.)
6. Click **Connect Gmail** in the menu bar panel and approve read-only access.
   Google will warn that the app is unverified — that's expected for a personal app;
   choose **Continue**.

**Staying signed in:** while the consent screen is in *Testing*, Google expires the sign-in
every 7 days. To avoid that, go to <https://console.cloud.google.com/auth/audience> and click
**Publish app**. Verification is not required for an app only you use; you'll just see the
"unverified app" notice once when connecting.

## Live carrier tracking (optional)

Doorstep asks the carriers directly, with free official developer credentials. **Every carrier is
optional:** connect only the ones you get packages from; the rest keep tracking from email.

| Carrier | Where to get free credentials | What to paste in Settings |
| --- | --- | --- |
| UPS | <https://developer.ups.com> → create an app with the **Tracking** API | Client ID + Client secret |
| USPS | <https://developers.usps.com> → create an app (includes **Tracking**) | Consumer key + Consumer secret |
| FedEx | <https://developer.fedex.com> → create a project with the **Track API** | API key + Secret key |
| DHL | <https://developer.dhl.com> → **Shipment Tracking – Unified** | API key |

In Doorstep: **Settings → Live tracking → Connect** next to a carrier. Credentials are checked
when you save and stored in Keychain.

For carriers without official credentials, an optional [17TRACK](https://api.17track.net) key
covers almost everything else (200 free tracking numbers on new accounts).

Active packages are checked every 30 minutes (10 while out for delivery). Carrier data overrides
email when it's newer. Amazon's own `TBA…` numbers and grocery deliveries can't be tracked outside
the store, so they stay email-only.

## How it works

| Piece | File |
| --- | --- |
| OAuth (loopback + PKCE), token in Keychain | `Sources/Doorstep/Gmail/GoogleAuth.swift` |
| Gmail search + message fetch | `Sources/Doorstep/Gmail/GmailClient.swift` |
| schema.org `Order`/`ParcelDelivery` markup | `Sources/Doorstep/Parsing/SchemaOrgParser.swift` |
| Patterns: status, tracking & order numbers, dates | `Sources/Doorstep/Parsing/Heuristics.swift` |
| On-device model (Foundation Models) | `Sources/Doorstep/Parsing/AIExtractor.swift` |
| Merging emails into orders | `Sources/Doorstep/Parsing/OrderBuilder.swift` |
| State, sync, notifications, spending | `Sources/Doorstep/Model/OrderStore.swift` |
| UPS, USPS, FedEx, DHL clients | `Sources/Doorstep/Gmail/CarrierTrackers.swift` |
| 17TRACK client (fallback) | `Sources/Doorstep/Gmail/TrackingService.swift` |
| Returns and return windows | `Sources/Doorstep/Model/Returns.swift` |

**Thumbnails**, in order of preference: the product photo from the email → a category icon when
the email names only a category (Amazon) → the store's logo → the carrier's logo → the store's
initial. Photos and logos are downloaded once and kept in `~/Library/Application Support/Doorstep/images`.
Logos come from the site's own app icon or DuckDuckGo's icon service.

Gmail (last 60 days) is checked every 15 minutes and on wake. Each email is parsed once and cached in
`~/Library/Application Support/Doorstep/state.json`.

## Tests

```sh
SDKROOT=$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.*.sdk | tail -1) \
  swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
```

The on-device model tests skip automatically where Apple Intelligence is off.

## Layout snapshots

```sh
build/Doorstep.app/Contents/MacOS/Doorstep --snapshot /tmp/doorstep-snaps
```

Renders every screen (light and dark) with sample data to PNGs; the README images come from these.

Debugging the parser:
- `Doorstep --search "<gmail query>"` lists matching emails (id, sender, subject).
- `Doorstep --dump <gmail message id>` prints the text and images the parser sees for one email.
