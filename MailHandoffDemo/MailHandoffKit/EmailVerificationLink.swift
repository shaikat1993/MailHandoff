//
//  EmailVerificationLink.swift
//  MailHandoffKit
//

import Foundation

/// A verification token. Never printed, logged, or sent to analytics —
/// `description` is redacted so string interpolation is safe.
public struct OpaqueToken: Equatable, Sendable, CustomStringConvertible {
    public let value: String

    /// Covers hex, base64, base64url, and JWTs. Narrow it in config if your backend
    /// uses a smaller alphabet.
    public static let defaultAllowedCharacters =
        CharacterSet.alphanumerics.union(.init(charactersIn: "-._~+/="))

    public init?(_ raw: String,
                 length: ClosedRange<Int> = 16...512,
                 allowed: CharacterSet = OpaqueToken.defaultAllowedCharacters) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // shape check only — real validation is the server's job
        guard length.contains(trimmed.count),
              trimmed.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        value = trimmed
    }

    public var description: String { "OpaqueToken(•••\(value.suffix(2)))" }
}

/// The parsed intent of an inbound URL.
public enum EmailVerificationLink: Equatable {
    case verify(token: OpaqueToken)

    /// Total function — any URL in, `nil` for anything unrecognised. Never crashes.
    public init?(url: URL, config: MailFlowConfiguration) {
        guard url.absoluteString.count <= 2048,
              let c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }

        let matchesCustom = config.customScheme.map {
            c.scheme == $0 && c.host == config.customSchemeHost
        } ?? false

        let matchesUniversal =
            c.scheme == "https" &&
            (c.host.map(config.universalLinkHosts.contains) ?? false) &&
            c.path == config.verifyPath

        guard matchesCustom || matchesUniversal,
              let raw = c.queryItems?.first(where: { $0.name == config.tokenQueryName })?.value,
              let token = OpaqueToken(raw,
                                      length: config.tokenLength,
                                      allowed: config.tokenAllowedCharacters) else { return nil }

        self = .verify(token: token)
    }
}
