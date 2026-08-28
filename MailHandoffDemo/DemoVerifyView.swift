//
//  DemoVerifyView.swift
//  MailHandoffDemo
//

import SwiftUI

struct DemoVerifyView: View {
    @EnvironmentObject private var mailFlow: MailFlowController
    @State private var email = "sadid@gmail.com"
    @State private var challenge = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Signed up with") {
                    TextField("email", text: $email)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                }

                Section("1 · Request the code + link") {
                    Button("Begin verification") {
                        challenge = mailFlow.beginVerification(for: email).codeChallenge
                    }
                    if !challenge.isEmpty {
                        LabeledContent("code_challenge", value: challenge)
                            .font(.caption.monospaced())
                            .lineLimit(1).truncationMode(.middle)
                    }
                }

                Section("2 · Go to the inbox") {
                    LabeledContent("Provider", value: String(describing: MailProvider(email: email)))
                    Button {
                        mailFlow.openMail(for: email)
                    } label: {
                        Label("Open Mail app", systemImage: "envelope")
                    }
                }

                Section("3 · Back from the link") {
                    switch mailFlow.verification {
                    case .idle:
                        Text(mailFlow.awaitingVerification ? "link received — verifying…" : "waiting for a link…")
                            .foregroundStyle(.secondary)
                    case .verifying:
                        HStack { ProgressView(); Text("verifying…") }
                    case .verified:
                        Label("verified", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                    case .failed(let error):
                        Label("failed — \(error)", systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                    }

                    if mailFlow.verification != .idle {
                        Button("Reset") { mailFlow.reset(); challenge = "" }
                    }
                }
            }
            .navigationTitle("Mail Flow")
            .onAppear { mailFlow.verifyPending() }
            .onChange(of: mailFlow.awaitingVerification) { _, awaiting in
                if awaiting { mailFlow.verifyPending() }   // link arrived while screen visible
            }
        }
    }
}

#Preview {
    DemoVerifyView()
        .environmentObject(MailFlowController(config: .demo, verifier: DemoVerifier()))
}
