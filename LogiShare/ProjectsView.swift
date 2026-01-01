import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ProjectsView: View {
    @EnvironmentObject private var store: LocalStore
    @EnvironmentObject private var auth: AuthManager

    @State private var importing = false
    @State private var search: String = ""

    @State private var sidebarWidth: CGFloat = 280
    private let sidebarMin: CGFloat = 220
    private let sidebarMax: CGFloat = 520

    private let logicxType: UTType = UTType(filenameExtension: "logicx") ?? .package

    private var meName: String? {
        auth.me?.displayName ?? auth.me?.email ?? auth.me?.id
    }

    private var filteredProjects: [Project] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return store.projects }
        return store.projects.filter {
            $0.name.localizedCaseInsensitiveContains(q) ||
            $0.localPath.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack {
                    Text("Active Projects").font(.headline)
                    Spacer()
                    Button { importing = true } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                }
                .padding([.horizontal, .top], 12)

                TextField("Search projects", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)

                List(filteredProjects, id: \.id, selection: $store.selectedProjectId) { p in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(p.name).font(.headline)
                            if p.isLocked {
                                Text("Locked")
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.orange.opacity(0.2))
                                    .cornerRadius(6)
                            }
                        }
                        Text(p.localPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 4)
                    .tag(p.id)
                }
                .listStyle(.sidebar)

                Divider()

                HStack {
                    if let id = store.selectedProjectId {
                        Button(role: .destructive) {
                            store.removeProject(projectId: id)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    } else {
                        Text("Select a project")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    }
                    Spacer()
                }
                .padding()
            }
            .frame(width: sidebarWidth)

            ResizableDivider(width: $sidebarWidth, minWidth: sidebarMin, maxWidth: sidebarMax)

            Group {
                if let id = store.selectedProjectId,
                   let p = store.projects.first(where: { $0.id == id }) {
                    ProjectDetailView(project: p)
                } else {
                    VStack(spacing: 12) {
                        ContentUnavailableView(
                            "No Project Selected",
                            systemImage: "folder",
                            description: Text("Import a .logicx project to get started.")
                        )

                        Button { importing = true } label: {
                            Label("Import .logicx Project", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: [logicxType, .package],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task {
                    await store.addProject(
                        from: url,
                        currentUserId: auth.me?.id,
                        currentUserName: meName
                    )
                }
            case .failure(let error):
                store.statusMessage = "Import cancelled/failed: \(error.localizedDescription)"
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) { Text("LogicShare").font(.headline) }
            ToolbarItem(placement: .primaryAction) {
                Button { importing = true } label: { Label("Import", systemImage: "square.and.arrow.down") }
            }
        }
    }
}

private struct ResizableDivider: View {
    @Binding var width: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat
    @State private var startWidth: CGFloat = 0

    var body: some View {
        ZStack {
            Rectangle().fill(Color.secondary.opacity(0.25)).frame(width: 1)
            Rectangle().fill(Color.clear).frame(width: 10)
        }
        .onHover { hovering in
            if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if startWidth == 0 { startWidth = width }
                    let proposed = startWidth + value.translation.width
                    width = Swift.min(Swift.max(proposed, minWidth), maxWidth)
                }
                .onEnded { _ in startWidth = 0 }
        )
    }
}

