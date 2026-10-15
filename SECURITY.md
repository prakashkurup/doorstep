# Security

Doorstep reads your email, so security reports are taken seriously.

## Reporting a vulnerability

Please **don't open a public issue.** Use GitHub's private reporting instead:
**Security → Report a vulnerability** on this repository. Include what you found, how to reproduce
it, and which version or commit you tested. You'll get a reply within a week.

## What Doorstep does with your data

- Gmail access is **read-only** (`gmail.readonly`), through an OAuth client you create in your own
  Google Cloud project. Nobody else's server is involved.
- Emails are parsed **on your Mac** and never uploaded. Cached orders live in
  `~/Library/Application Support/Doorstep/state.json`.
- The Google refresh token and any carrier API keys are stored in the **macOS Keychain**.
- Live tracking (optional) sends only tracking numbers, only to carriers you connect.

## Things worth reporting

- Any path where email content, tokens or keys leave the Mac other than as described above.
- Tokens or keys written to disk outside the Keychain, or printed to logs.
- Weaknesses in the OAuth loopback sign-in (PKCE, state checks, the local listener).
