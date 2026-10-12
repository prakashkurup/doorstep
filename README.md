# Doorstep

A macOS menu bar app that shows the status of your orders, read from shipping emails in Gmail.

- **Today / Tomorrow / Later this week / Delivered** at a glance, with a 4-step progress track
- **Week strip**: the next 7 days with a dot per expected delivery; click a day to filter
- Click any order for its timeline, tracking number and a one-click carrier link
- **Live carrier tracking** (optional, official UPS/USPS/FedEx/DHL APIs): every scan, delivery windows, earlier delay alerts
- **Return deadlines**: "Return by Nov 9" on delivered orders (stated in the email, or the store's usual window, marked *est.*), a *Return soon* section, and a reminder 3 days before
- **Returns**: return started → sent back → received → refunded, plus refunds for unavailable items
- **Monthly spending** by store from order totals in your email
- **Signature required** badge when someone needs to be home
- Notifications only for *out for delivery*, *delivered*, *delayed* and closing return windows
- Read-only Gmail access; order details are extracted **on this Mac** (patterns + schema.org markup + Apple's on-device model). Nothing is sent to any server other than Gmail itself.

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

Renders every screen (light and dark) with sample data to PNGs.

`Doorstep --dump <gmail message id>` prints the text and images the parser sees for one email.
