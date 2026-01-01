import SwiftUI

@main
struct LogicShareApp: App {
    @StateObject private var store = LocalStore()
    @StateObject private var auth = AuthManager() // MockAuthAPI for now

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(auth)
                .frame(minWidth: 1050, minHeight: 650)
        }
        .windowToolbarStyle(.unified)
    }
}

