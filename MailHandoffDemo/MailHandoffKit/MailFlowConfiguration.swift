//
//  MailFlowConfiguration.swift
//  MailHandoffKit
//

import Foundation

/// Everything app-specific about the mail flow. The kit carries no scheme, host,
/// path, or bundle id of its own — you pass one of these.
public struct MailFlowConfiguration: Sendable {

    // Return deep link
    public var customScheme: String?              // e.g. "myapp" — nil disables the custom-scheme path (most secure)
    public var customSchemeHost: String           // e.g. "verify" → myapp://verify?token=…
    public var universalLinkHosts: Set<String>    // e.g. ["myapp.example"]
    public var verifyPath: String                 // "/auth/verify"
    public var tokenQueryName: String             // "token"
    public var tokenLength: ClosedRange<Int>      // accepted token length
    public var tokenAllowedCharacters: CharacterSet // confirm with your backend

    // Hand-off
    public var genericWebFallback: URL            // unknown domain + no mail app installed

    // Ops
    public var loggingSubsystem: String

    public init(customScheme: String? = nil,
                customSchemeHost: String = "verify",
                universalLinkHosts: Set<String> = [],
                verifyPath: String = "/auth/verify",
                tokenQueryName: String = "token",
                tokenLength: ClosedRange<Int> = 16...512,
                tokenAllowedCharacters: CharacterSet = OpaqueToken.defaultAllowedCharacters,
                genericWebFallback: URL = URL(string: "https://mail.google.com/")!,
                loggingSubsystem: String) {
        self.customScheme = customScheme
        self.customSchemeHost = customSchemeHost
        self.universalLinkHosts = universalLinkHosts
        self.verifyPath = verifyPath
        self.tokenQueryName = tokenQueryName
        self.tokenLength = tokenLength
        self.tokenAllowedCharacters = tokenAllowedCharacters
        self.genericWebFallback = genericWebFallback
        self.loggingSubsystem = loggingSubsystem
    }
}

#if DEBUG
public extension MailFlowConfiguration {
    /// Call at launch. Trips if Info.plist is missing entries the kit needs.
    func assertInfoPlistIsValid(_ bundle: Bundle = .main) {
        let schemes = Set(bundle.object(forInfoDictionaryKey: "LSApplicationQueriesSchemes") as? [String] ?? [])
        let missing = Set(MailClient.allCases.map(\.queryScheme)).subtracting(schemes)
        assert(missing.isEmpty, "MailHandoffKit: add to LSApplicationQueriesSchemes → \(missing.sorted())")

        if let customScheme {
            let declared = (bundle.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]])?
                .flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] } ?? []
            assert(declared.contains(customScheme), "MailHandoffKit: add '\(customScheme)' to CFBundleURLTypes")
        }
    }
}
#endif
