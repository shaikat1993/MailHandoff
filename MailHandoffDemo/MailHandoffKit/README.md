# MailHandoffKit

Take the user to their mail app, then bring them back from the emailed link and
verify — provider-aware, config-driven, no host knowledge baked in.

## Files

| File | Role |
|---|---|
| `MailFlowConfiguration.swift` | every app-specific value (scheme, domain, paths, token rules) |
| `MailApps.swift` | `MailClient`, `MailProvider` (domain → service), `MailRouter` (the pure ladder) |
| `EmailVerificationLink.swift` | `OpaqueToken` + the total URL parser |
| `PKCE.swift` | RFC 7636 device binding |
| `VerifierStore.swift` | holds the PKCE secret between request and redemption |
| `MailFlowController.swift` | the one `@MainActor ObservableObject` the host talks to |

## Integrate (5 steps)

```swift
// 1. Info.plist
//    LSApplicationQueriesSchemes: googlegmail, ms-outlook, ymail, protonmail, readdle-spark, message
//    CFBundleURLTypes: your custom scheme (optional — Universal Links are the secure path)

// 2. Config, in your app:
extension MailFlowConfiguration {
    static let app = MailFlowConfiguration(
        customScheme: nil,                              // nil = Universal Links only (recommended)
        universalLinkHosts: ["yourapp.example"],
        loggingSubsystem: "com.yourcompany.yourapp"
    )
}

// 3. Implement the backend seam:
struct LiveEmailVerifier: EmailVerifying {
    func verify(token: OpaqueToken, codeVerifier: String, expectedEmail: String) async throws {
        var req = URLRequest(url: URL(string: "https://yourapp.example/auth/verifyEmailToken")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode([
            "token": token.value, "code_verifier": codeVerifier, "email": expectedEmail
        ])
        let (_, resp) = try await URLSession.shared.data(for: req)
        switch (resp as? HTTPURLResponse)?.statusCode {
        case 200:      return
        case 410, 404: throw EmailVerificationError.invalidOrExpired
        case 403:      throw EmailVerificationError.wrongAccount
        default:       throw EmailVerificationError.network
        }
    }
}

// 4. App:
@StateObject private var mailFlow = MailFlowController(config: .app, verifier: LiveEmailVerifier())
// body:
RootView()
    .environmentObject(mailFlow)
    .onOpenURL { mailFlow.handle($0) }

// 5. Verify screen:
@EnvironmentObject var mailFlow: MailFlowController

// when you ask the backend to send the code + link:
let request = mailFlow.beginVerification(for: email)
// → include request.codeChallenge in that API call

Button("Open Mail app") { mailFlow.openMail(for: email) }

.onAppear { mailFlow.verifyPending() }                       // user is present → safe to verify
.onChange(of: mailFlow.awaitingVerification) { _, a in if a { mailFlow.verifyPending() } }
// observe mailFlow.verification == .verified → proceed
```

## Security model

**In the kit:**
- token is opaque, redacted in `description`, never logged (URL logs are scheme/host/path only)
- input bounds — URL ≤ 2048, token length + alphabet from config
- Universal Links host-pinned; custom scheme is opt-in and off by default
- **PKCE** — the link is bound to the device that requested it; an intercepted or
  forwarded link can't be redeemed without the on-device verifier
- verification is a **server round-trip** — the client never flips state locally
- token is **buffered**, not auto-run — `verifyPending()` runs only from a visible
  screen (user present); cold start with no verifier **fails closed**
- in-flight verification is cancelled if a new one starts; last token stored only as a hash

**Your backend must enforce (the kit cannot):**
- token ≥ 128-bit entropy, **single-use**, ≤ 10 min TTL, invalidated on redeem
- verify `code_verifier` against the stored `code_challenge` (S256)
- token bound to the account/request that issued it — reject cross-account (`403`)
- rate-limit `POST /auth/verifyEmailToken`
- redeeming the token flips "email verified" — it does **not** by itself mint a session
- AASA scoped to exactly `/auth/verify` + `token` query, **no path wildcards**
- verification email + landing page: `Referrer-Policy: no-referrer`, no analytics on the token
- confirm the token alphabet matches `MailFlowConfiguration.tokenAllowedCharacters`

## Notes

- Uses `ObservableObject` (not `@Observable`) for iOS 15+ / legacy-codebase compatibility.
- `InMemoryVerifierStore` loses the verifier on cold start by design (fail closed).
  Inject a Keychain-backed `VerifierStoring` if the link must survive app termination.
- The kit does not navigate — pair `mailFlow.verification` / `awaitingVerification`
  with your router to present the verify screen.
