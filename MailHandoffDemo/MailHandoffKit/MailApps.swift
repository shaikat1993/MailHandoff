//
//  MailApps.swift
//  MailHandoffKit
//

import Foundation

/// A mail app the kit can open via its published URL scheme.
public enum MailClient: String, CaseIterable, Sendable {
    case appleMail, gmail, outlook, yahoo, proton, spark

    /// Launches the app (foreground only — iOS can't open a specific message or inbox).
    public var launchURL: URL {
        switch self {
        case .appleMail: return URL(string: "message://")!
        case .gmail:     return URL(string: "googlegmail://")!
        case .outlook:   return URL(string: "ms-outlook://")!
        case .yahoo:     return URL(string: "ymail://")!
        case .proton:    return URL(string: "protonmail://")!
        case .spark:     return URL(string: "readdle-spark://")!
        }
    }

    /// Must be in `LSApplicationQueriesSchemes` or `canOpenURL` silently returns false.
    public var queryScheme: String {
        switch self {
        case .appleMail: return "message"
        case .gmail:     return "googlegmail"
        case .outlook:   return "ms-outlook"
        case .yahoo:     return "ymail"
        case .proton:    return "protonmail"
        case .spark:     return "readdle-spark"
        }
    }

    public var displayName: String {
        switch self {
        case .appleMail: return "Apple Mail"
        case .gmail:     return "Gmail"
        case .outlook:   return "Outlook"
        case .yahoo:     return "Yahoo Mail"
        case .proton:    return "Proton Mail"
        case .spark:     return "Spark"
        }
    }
}

/// Best-effort guess of the user's mail service from their address domain.
public enum MailProvider: Equatable, Sendable {
    case gmail, outlook, yahoo, proton, icloud, unknown

    public init(email: String) {
        let domain = email.split(separator: "@").last.map { $0.lowercased() } ?? ""
        switch domain {
        case "gmail.com", "googlemail.com":
            self = .gmail
        case "outlook.com", "hotmail.com", "hotmail.co.uk", "live.com", "msn.com":
            self = .outlook
        case "yahoo.com", "yahoo.co.uk", "ymail.com", "rocketmail.com":
            self = .yahoo
        case "proton.me", "protonmail.com", "pm.me":
            self = .proton
        case "icloud.com", "me.com", "mac.com":
            self = .icloud
        default:
            self = .unknown
        }
    }

    var preferredApp: MailClient? {
        switch self {
        case .gmail:   return .gmail
        case .outlook: return .outlook
        case .yahoo:   return .yahoo
        case .proton:  return .proton
        case .icloud:  return .appleMail
        case .unknown: return nil
        }
    }

    var webmailURL: URL? {
        switch self {
        case .gmail:   return URL(string: "https://mail.google.com/")
        case .outlook: return URL(string: "https://outlook.live.com/mail/")
        case .yahoo:   return URL(string: "https://mail.yahoo.com/")
        case .proton:  return URL(string: "https://mail.proton.me/")
        case .icloud:  return URL(string: "https://www.icloud.com/mail/")
        case .unknown: return nil
        }
    }
}

/// Where `openMail(for:)` decided to send the user.
public enum MailDestination: Equatable, Sendable {
    case app(MailClient)
    case web(URL)

    var logDescription: String {
        switch self {
        case .app(let client): return "app:\(client.rawValue)"
        case .web(let url):    return "web:\(url.host ?? "?")"
        }
    }
}

@MainActor
enum MailRouter {
    /// provider app installed → provider webmail → Apple Mail (corp/IMAP) → generic web
    static func destination(for email: String,
                            config: MailFlowConfiguration,
                            opener: URLOpening) -> MailDestination {
        let provider = MailProvider(email: email)
        if let app = provider.preferredApp, opener.canOpen(app.launchURL) { return .app(app) }
        if let web = provider.webmailURL { return .web(web) }
        if opener.canOpen(MailClient.appleMail.launchURL) { return .app(.appleMail) }
        return .web(config.genericWebFallback)
    }
}
