import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: LocalStore
    @EnvironmentObject private var auth: AuthManager

    @State private var tab: SidebarTab = .projects

    var body: some View {
        Group {
            if auth.isLoggedIn {
                NavigationSplitView {
                    List(selection: $tab) {
                        ForEach(SidebarTab.allCases) { t in
                            Label(t.rawValue, systemImage: icon(for: t))
                                .tag(t)
                        }
                    }
                    .listStyle(.sidebar)
                } detail: {
                    ZStack(alignment: .bottom) {
                        switch tab {
                        case .projects: ProjectsView()
                        case .activity: ActivityView()
                        case .people: PeopleView()
                        case .account: AccountView()
                        }

                        if let msg = store.statusMessage {
                            StatusBar(message: msg)
                                .padding(.horizontal, 12)
                                .padding(.bottom, 10)
                        }
                    }
                }
            } else {
                LoginView()
            }
        }
        .onAppear {
            // If tokens exist in keychain, AuthManager loads them; this ensures /me runs.
            Task { await auth.loadMe() }
        }
    }

    private func icon(for tab: SidebarTab) -> String {
        switch tab {
        case .projects: return "folder"
        case .activity: return "clock"
        case .people: return "person.2"
        case .account: return "person.crop.circle"
        }
    }
}

private struct StatusBar: View {
    let message: String
    var body: some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(.thinMaterial)
            .cornerRadius(10)
    }
}

