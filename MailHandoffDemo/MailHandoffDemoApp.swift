//
//  MailHandoffDemoApp.swift
//  MailHandoffDemo
//

import SwiftUI

/// App-specific config lives here, never in the kit — proof the kit knows nothing
/// about "mhdemo" or our domain.
extension MailFlowConfiguration {
    static let demo = MailFlowConfiguration(
        customScheme: "mhdemo",
        universalLinkHosts: ["crowdsorsa.com"],
        loggingSubsystem: "com.sadid.MailHandoffDemo"
    )
}

/// Stand-in for the real backend. Replace with a URLSession call to
/// POST /auth/verifyEmailToken { token, code_verifier, email }.
struct DemoVerifier: EmailVerifying {
    var outcome: Result<Void, EmailVerificationError> = .success(())
    var delay: Duration = .seconds(1)
    func verify(token: OpaqueToken, codeVerifier: String, expectedEmail: String) async throws {
        try await Task.sleep(for: delay)
        if case .failure(let error) = outcome { throw error }
    }
}

@main
struct MailHandoffDemoApp: App {
    @StateObject private var mailFlow = MailFlowController(config: .demo, verifier: DemoVerifier())

    init() {
        #if DEBUG
        MailFlowConfiguration.demo.assertInfoPlistIsValid()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            DemoVerifyView()
                .environmentObject(mailFlow)
                .onOpenURL { mailFlow.handle($0) }
        }
    }
}
