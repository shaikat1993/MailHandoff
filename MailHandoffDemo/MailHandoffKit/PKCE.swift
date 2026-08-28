//
//  PKCE.swift
//  MailHandoffKit
//

import Foundation
import CryptoKit

/// RFC 7636 PKCE — binds the verification link to the device that requested it.
///
/// Flow: the app makes a random `verifier` and keeps it on-device; it sends only
/// `challenge = base64url(SHA256(verifier))` with the "email me the link" request.
/// Redeeming the token requires the verifier. An intercepted link is worthless
/// without it — this is what closes the custom-scheme hijack / link-forwarding hole.
public enum PKCE {

    /// 256 bits from the system CSPRNG, base64url. Never leaves the device.
    public static func makeVerifier() -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in generator.next() as UInt8 }
        return base64URL(Data(bytes))
    }

    /// Safe to send with the link request.
    public static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
