//
//  MailHandoffDemoTests.swift
//  MailHandoffDemoTests
//

import Testing
import Foundation
@testable import MailHandoffDemo

private let config = MailFlowConfiguration(
    customScheme: "mhdemo",
    universalLinkHosts: ["crowdsorsa.com"],
    loggingSubsystem: "test"
)
private let validToken = "demo-token-abcdef123456"

// MARK: - Provider mapping

@Suite("MailProvider")
struct MailProviderTests {
    @Test(arguments: [
        ("a@gmail.com", MailProvider.gmail),
        ("a@googlemail.com", .gmail),
        ("a@hotmail.co.uk", .outlook),
        ("a@yahoo.com", .yahoo),
        ("a@proton.me", .proton),
        ("a@icloud.com", .icloud),
        ("a@crowdsorsa.com", .unknown),
        ("garbage", .unknown),
        ("", .unknown),
    ])
    func maps(_ email: String, _ expected: MailProvider) {
        #expect(MailProvider(email: email) == expected)
    }
}

// MARK: - Link parsing / hostile input

@Suite("EmailVerificationLink")
struct LinkParsingTests {
    @Test(arguments: [
        "mhdemo://verify",
        "mhdemo://verify?token=",
        "mhdemo://verify?token=short",
        "mhdemo://verify?token=has%20space",
        "mhdemo://settings?token=\(validToken)",
        "https://evil.com/auth/verify?token=\(validToken)",
        "https://crowdsorsa.com/other?token=\(validToken)",
        "javascript:alert(1)",
    ])
    func rejectsHostileURLs(_ raw: String) {
        #expect(EmailVerificationLink(url: URL(string: raw)!, config: config) == nil)
    }

    @Test func acceptsCustomScheme() {
        let link = EmailVerificationLink(url: URL(string: "mhdemo://verify?token=\(validToken)")!, config: config)
        #expect(link == .verify(token: OpaqueToken(validToken)!))
    }

    @Test func acceptsUniversalLink() {
        let url = URL(string: "https://crowdsorsa.com/auth/verify?token=\(validToken)")!
        #expect(EmailVerificationLink(url: url, config: config) != nil)
    }
}

@Suite("OpaqueToken")
struct OpaqueTokenTests {
    @Test func redactsInDescription() {
        #expect(!"\(OpaqueToken("supersecretvalue1234")!)".contains("supersecret"))
    }
    @Test func respectsConfiguredAlphabet() {
        #expect(OpaqueToken("abc==", length: 1...100, allowed: .alphanumerics) == nil)
        #expect(OpaqueToken("abc==", length: 1...100, allowed: .alphanumerics.union(.init(charactersIn: "="))) != nil)
    }
}

// MARK: - The resolution ladder

@MainActor
@Suite("MailRouter")
struct MailRouterTests {
    struct FakeOpener: URLOpening {
        var installed: Set<String>
        func canOpen(_ url: URL) -> Bool { installed.contains(url.scheme ?? "") }
        func open(_ url: URL, then completion: ((Bool) -> Void)?) { completion?(true) }
    }

    @Test func providerAppWhenInstalled() {
        let d = MailRouter.destination(for: "x@gmail.com", config: config,
                                      opener: FakeOpener(installed: ["googlegmail"]))
        #expect(d == .app(.gmail))
    }
    @Test func providerWebWhenAppMissing() {
        let d = MailRouter.destination(for: "x@gmail.com", config: config,
                                      opener: FakeOpener(installed: []))
        #expect(d == .web(URL(string: "https://mail.google.com/")!))
    }
    @Test func unknownDomainFallsToAppleMail() {
        let d = MailRouter.destination(for: "x@corp.com", config: config,
                                      opener: FakeOpener(installed: ["message"]))
        #expect(d == .app(.appleMail))
    }
    @Test func unknownDomainNoAppsFallsToGenericWeb() {
        let d = MailRouter.destination(for: "x@corp.com", config: config,
                                      opener: FakeOpener(installed: []))
        #expect(d == .web(config.genericWebFallback))
    }
}

// MARK: - Controller: the security-relevant behaviour

@MainActor
@Suite("MailFlowController")
struct ControllerTests {
    struct StubVerifier: EmailVerifying {
        var result: Result<Void, EmailVerificationError>
        func verify(token: OpaqueToken, codeVerifier: String, expectedEmail: String) async throws {
            if case .failure(let e) = result { throw e }
        }
    }
    struct NoopOpener: URLOpening {
        func canOpen(_ url: URL) -> Bool { false }
        func open(_ url: URL, then completion: ((Bool) -> Void)?) { completion?(true) }
    }

    private func makeController(_ r: Result<Void, EmailVerificationError>) -> MailFlowController {
        MailFlowController(config: config, verifier: StubVerifier(result: r),
                           opener: NoopOpener(), verifierStore: InMemoryVerifierStore())
    }

    private func settle() async { try? await Task.sleep(for: .milliseconds(80)) }

    @Test func happyPath() async {
        let c = makeController(.success(()))
        _ = c.beginVerification(for: "a@gmail.com")
        c.handle(URL(string: "mhdemo://verify?token=\(validToken)")!)
        c.verifyPending()
        await settle()
        #expect(c.verification == .verified)
    }

    @Test func forgedTokenNeverVerifiesLocally() async {
        let c = makeController(.failure(.invalidOrExpired))
        _ = c.beginVerification(for: "a@gmail.com")
        c.handle(URL(string: "mhdemo://verify?token=forged-abcdef1234")!)
        c.verifyPending()
        await settle()
        #expect(c.verification == .failed(.invalidOrExpired))
    }

    @Test func coldStartWithoutPKCEVerifierFailsClosed() async {
        let c = makeController(.success(()))
        c.handle(URL(string: "mhdemo://verify?token=\(validToken)")!)   // no beginVerification
        c.verifyPending()
        #expect(c.verification == .failed(.missingContext))
    }

    @Test func duplicateLinkIsIgnored() async {
        let c = makeController(.success(()))
        _ = c.beginVerification(for: "a@gmail.com")
        let url = URL(string: "mhdemo://verify?token=\(validToken)")!
        c.handle(url)
        #expect(c.awaitingVerification)
        c.verifyPending()
        await settle()
        c.handle(url)                              // same token again
        #expect(!c.awaitingVerification)           // not re-buffered
    }

    @Test func pkceChallengeIsDeterministicButVerifierIsUnique() {
        let v = PKCE.makeVerifier()
        #expect(PKCE.challenge(for: v) == PKCE.challenge(for: v))
        #expect(PKCE.makeVerifier() != PKCE.makeVerifier())
    }
}
