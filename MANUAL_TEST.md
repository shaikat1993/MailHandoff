# Manual acceptance test

If all of this passes, the kit is done and the only remaining work is implementing
`EmailVerifying` against a real backend.

## Pre-flight

```bash
xcodebuild test -project MailHandoffDemo.xcodeproj -scheme MailHandoffDemo \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:MailHandoffDemoTests CODE_SIGNING_ALLOWED=NO
```

Expect **TEST SUCCEEDED** (30 cases): pure logic + security behaviours
(forged token → `.failed`, cold start → fail closed, duplicate ignored,
hostile URLs rejected).

## Run + watch logs

```bash
xcrun simctl boot "iPhone 17 Pro" 2>/dev/null
open -a Simulator
APP=$(find ~/Library/Developer/Xcode/DerivedData -name MailHandoffDemo.app -path '*Debug-iphonesimulator*' | head -1)
xcrun simctl install booted "$APP"
xcrun simctl launch booted com.sadid.MailHandoffDemo

# second terminal
xcrun simctl spawn booted log stream --level info \
  --predicate 'subsystem == "com.sadid.MailHandoffDemo"'
```

## Matrix

Valid token: `demo-token-abcdef123456`

| # | Action | Expected in app | Expected log | Proves |
|---|---|---|---|---|
| 1 | Type `sadid@gmail.com`, tap **Begin verification** | a `code_challenge` appears | — | PKCE verifier stored, challenge derived |
| 2 | Check **Provider** row for `@gmail.com` / `@outlook.com` / `@yahoo.com` / `@acme-corp.com` | `gmail` / `outlook` / `yahoo` / `unknown` | — | domain → provider mapping |
| 3 | With `@gmail.com`, tap **Open Mail app** | Safari opens `mail.google.com` | `open mail web:mail.google.com` | provider-aware routing + web fallback |
| 4 | `xcrun simctl openurl booted "mhdemo://verify?token=demo-token-abcdef123456"` | foreground → `verifying…` → **verified** | `link accepted mhdemo://verify` | full round trip: buffer → verifyPending → PKCE verifier → EmailVerifying → success |
| 5 | Fire the same URL again | stays `verified`, no spinner | `link duplicate mhdemo://verify` | idempotency guard (hashed) |
| 6 | Tap **Reset**, then `simctl openurl "mhdemo://verify"` | nothing | `link rejected mhdemo://verify` | missing-token rejected |
| 7 | `simctl openurl "mhdemo://verify?token=abc"` | nothing | `link rejected` | length bound |
| 8 | `simctl openurl "https://evil.com/auth/verify?token=demo-token-abcdef123456"` | Safari loads evil.com, app untouched | *(nothing)* | Universal-Link host pinning |
| 9 | `xcrun simctl terminate booted com.sadid.MailHandoffDemo`, then fire the valid URL **without** tapping Begin verification first | launches → **failed — missingContext** | `link accepted` then `verify aborted — no PKCE verifier` | intercepted/forwarded link is dead without the on-device verifier |
| 10 | Search the log output for `demo-token` or `code_verifier` | — | **never appears** | log redaction |

On a real device: replace `simctl openurl` with typing the URL in Safari's address bar → Go → Open.

## What #4 does NOT prove

`DemoVerifier` always returns success, so a well-formed **forged** token also shows
"verified" in the demo. The stub isn't a server. The real property
("forged/expired token → `.failed`") is covered by the unit test
`forgedTokenNeverVerifiesLocally` and enforced by the backend returning `410`/`404`.

## Going live

1. Implement `EmailVerifying` (see `MailHandoffKit/README.md`).
2. `MailFlowController(config: .app, verifier: LiveEmailVerifier())` — was `DemoVerifier()`.
3. Production only: `customScheme: nil`, add the `applinks:` entitlement + AASA,
   hand the backend team the "your backend must enforce" list.
