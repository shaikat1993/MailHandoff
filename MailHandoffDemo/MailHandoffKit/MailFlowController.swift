//
//  MailFlowController.swift
//  MailHandoffKit
//

import UIKit
import Combine
import OSLog
import CryptoKit

// MARK: - The backend seam — implement this against your real API

/// Redeems a token for a server decision. The token is a *claim* the client forwards;
/// only the server confirms it. `codeVerifier` is the PKCE secret; `expectedEmail`
/// lets the server reject a token minted for another account.
public protocol EmailVerifying: Sendable {
    func verify(token: OpaqueToken, codeVerifier: String, expectedEmail: String) async throws
}

public enum EmailVerificationError: Error, Equatable, Sendable {
    case invalidOrExpired
    case wrongAccount
    case missingContext   // no PKCE verifier on device (e.g. cold start) — re-request
    case network
}

// MARK: - URL opening (injectable for tests)

@MainActor
public protocol URLOpening {
    func canOpen(_ url: URL) -> Bool
    func open(_ url: URL, then completion: ((Bool) -> Void)?)
}

public struct SystemURLOpener: URLOpening {
    public init() {}
    public func canOpen(_ url: URL) -> Bool { UIApplication.shared.canOpenURL(url) }
    public func open(_ url: URL, then completion: ((Bool) -> Void)?) {
        UIApplication.shared.open(url, options: [:], completionHandler: completion)
    }
}

// MARK: - The one object the host talks to

@MainActor
public final class MailFlowController: ObservableObject {

    public enum VerificationState: Equatable {
        case idle
        case verifying
        case verified
        case failed(EmailVerificationError)
    }

    /// Include `codeChallenge` in the request that asks the backend to send the code + link.
    public struct LinkRequest: Equatable, Sendable {
        public let email: String
        public let codeChallenge: String
    }

    @Published public private(set) var verification: VerificationState = .idle
    /// True once a valid return link is buffered and waiting for `verifyPending()`.
    @Published public private(set) var awaitingVerification = false

    private let config: MailFlowConfiguration
    private let verifier: EmailVerifying
    private let opener: URLOpening
    private let store: VerifierStoring
    private let log: Logger

    private var expectedEmail: String?
    private var pendingToken: OpaqueToken?
    private var lastTokenHash: String?
    private var task: Task<Void, Never>?

    public init(config: MailFlowConfiguration,
                verifier: EmailVerifying,
                opener: URLOpening? = nil,
                verifierStore: VerifierStoring? = nil) {
        self.config = config
        self.verifier = verifier
        self.opener = opener ?? SystemURLOpener()
        self.store = verifierStore ?? InMemoryVerifierStore()
        self.log = Logger(subsystem: config.loggingSubsystem, category: "mail-flow")
    }

    // MARK: 1 · when you ask the backend to send the code + link

    public func beginVerification(for email: String) -> LinkRequest {
        let secret = PKCE.makeVerifier()
        store.save(secret, for: email)
        expectedEmail = email
        verification = .idle
        return LinkRequest(email: email, codeChallenge: PKCE.challenge(for: secret))
    }

    // MARK: 2 · send the user to their mail app

    public func openMail(for email: String) {
        let destination = MailRouter.destination(for: email, config: config, opener: opener)
        let url = { switch destination { case .app(let c): return c.launchURL; case .web(let u): return u } }()
        opener.open(url) { [weak self] opened in
            guard let self, !opened, case .app = destination,
                  let web = MailProvider(email: email).webmailURL else { return }
            self.opener.open(web, then: nil)
            self.log.info("open mail fell back to web")
        }
        log.info("open mail \(destination.logDescription, privacy: .public)")
    }

    // MARK: 3 · the return link — buffer only; verify when the screen is on-screen

    public func handle(_ url: URL) {
        guard case .verify(let token)? = EmailVerificationLink(url: url, config: config) else {
            log.info("link rejected \(url.shape, privacy: .public)")
            return
        }
        let hash = Self.hash(token.value)
        guard hash != lastTokenHash else {
            log.info("link duplicate \(url.shape, privacy: .public)")
            return
        }
        lastTokenHash = hash
        pendingToken = token
        awaitingVerification = true
        log.info("link accepted \(url.shape, privacy: .public)")
    }

    /// Call from the verify screen once it is visible (the user is present).
    public func verifyPending() {
        guard let token = pendingToken else { return }
        pendingToken = nil
        awaitingVerification = false

        guard let email = expectedEmail, let secret = store.take(for: email) else {
            verification = .failed(.missingContext)
            log.error("verify aborted — no PKCE verifier (cold start?)")
            return
        }

        task?.cancel()
        task = Task { [weak self] in
            await self?.run(token: token, verifier: secret, email: email)
        }
    }

    public func reset() {
        task?.cancel()
        verification = .idle
        pendingToken = nil
        lastTokenHash = nil
        awaitingVerification = false
    }

    private func run(token: OpaqueToken, verifier secret: String, email: String) async {
        verification = .verifying
        do {
            try await verifier.verify(token: token, codeVerifier: secret, expectedEmail: email)
            guard !Task.isCancelled else { return }
            verification = .verified
        } catch is CancellationError {
            return
        } catch let error as EmailVerificationError {
            verification = .failed(error)
        } catch {
            verification = .failed(.network)
        }
    }

    private static func hash(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

private extension URL {
    /// scheme://host/path — deliberately drops the query (tokens live there).
    var shape: String {
        let c = URLComponents(url: self, resolvingAgainstBaseURL: false)
        return "\(c?.scheme ?? "?")://\(c?.host ?? "?")\(c?.path ?? "")"
    }
}
