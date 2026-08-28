//
//  VerifierStore.swift
//  MailHandoffKit
//

import Foundation

/// Holds the PKCE verifier between "request the link" and "redeem the token".
///
/// The default `InMemoryVerifierStore` is deliberately non-persistent: a cold start
/// loses the verifier and `verifyPending()` fails closed (`.missingContext`), so the
/// user simply re-requests. That is a safe posture. If you need the link to survive
/// app termination, inject a Keychain-backed implementation.
public protocol VerifierStoring: Sendable {
    func save(_ verifier: String, for email: String)
    /// Read once, then delete — a verifier is single-use.
    func take(for email: String) -> String?
}

public final class InMemoryVerifierStore: VerifierStoring, @unchecked Sendable {
    // @unchecked: mutable dictionary guarded by the lock below.
    private let lock = NSLock()
    private var storage: [String: String] = [:]

    public init() {}

    public func save(_ verifier: String, for email: String) {
        lock.withLock { storage[email.lowercased()] = verifier }
    }

    public func take(for email: String) -> String? {
        lock.withLock {
            let key = email.lowercased()
            defer { storage[key] = nil }
            return storage[key]
        }
    }
}
