    import SwiftUI

    enum TopTab: String, CaseIterable {
        case account = "Account"
        case projects = "Projects"
        case friends = "Friends"
    }

    struct ContentView: View {
        @State private var tab: TopTab = .account

        var body: some View {
            VStack {
                switch tab {
                case .account: Text("Account view")
                case .projects: Text("Projects view")
                case .friends: Text("Friends view")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Picker("", selection: $tab) {
                        ForEach(TopTab.allCases, id: \.self) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)  
                    .labelsHidden()
                }
            }
        }
    }
    #Preview {
        ContentView()
    }
