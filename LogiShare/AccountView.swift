import SwiftUI

struct AccountView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var store: LocalStore

    @State private var displayName: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Account").font(.title2).bold()

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    if let me = auth.me {
                        Text(me.displayName ?? "Signed in")
                            .font(.headline)
                        Text(me.email)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            if me.subscriptionActive {
                                Label("Subscription Active", systemImage: "checkmark.seal.fill")
                                    .foregroundStyle(.green)
                            } else {
                                Label("Subscription Inactive", systemImage: "xmark.seal")
                                    .foregroundStyle(.red)
                            }
                        }
                    } else {
                        Text("Loading profile…")
                            .foregroundStyle(.secondary)
                    }

                    if let err = auth.authError {
                        Text(err)
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }

            HStack {
                Button("Refresh") {
                    Task { await auth.loadMe() }
                }

                Spacer()

                Button(role: .destructive) {
                    auth.logout()
                    store.statusMessage = "Logged out"
                } label: {
                    Text("Log Out")
                }
            }

            Divider().padding(.vertical, 6)

            Text("Signup & billing")
                .font(.headline)
            Text("Users sign up and manage billing on the website. The app only logs in and checks subscription status.")
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding()
        .onAppear {
            displayName = auth.me?.displayName ?? ""
        }
    }
}

