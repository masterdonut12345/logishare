import SwiftUI
import AppKit

struct ProjectDetailView: View {
    @EnvironmentObject private var store: LocalStore
    @EnvironmentObject private var auth: AuthManager

    let project: Project

    @State private var versionMessage: String = ""
    @State private var fileSearch: String = ""
    @State private var selectedVersionId: UUID?

    // Sheets
    @State private var showingShareSheet = false

    // Share form
    @State private var newMemberId: String = ""
    @State private var newMemberRole: ProjectRole = .editor

    private var isOwner: Bool {
        guard let ownerId = project.ownerUserId, let meId = auth.me?.id else { return true }
        return ownerId == meId
    }

    private var meName: String? {
        // Change this if your AuthManager uses a different field name
        auth.me?.displayName ?? auth.me?.email ?? auth.me?.id
    }

    var body: some View {
        let versions = project.versions
        let selectedId = selectedVersionId ?? versions.first?.id
        let selectedVersion = versions.first(where: { $0.id == selectedId }) ?? versions.first

        VStack(alignment: .leading, spacing: 12) {
            header(selectedVersion: selectedVersion)

            HStack(alignment: .top, spacing: 12) {
                versionsPanel(versions: versions)
                    .frame(minWidth: 280, maxWidth: 360)

                Divider()

                filesPanel(version: selectedVersion)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding()
        .onAppear {
            if selectedVersionId == nil { selectedVersionId = versions.first?.id }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Share…") { showingShareSheet = true }
                    .disabled(!isOwner)
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            shareSheet
        }
    }

    // MARK: - Header

    private func header(selectedVersion: ProjectVersion?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(project.name).font(.title2).bold()
                Spacer()

                Toggle(isOn: Binding(
                    get: { project.isLocked },
                    set: { _ in
                        Task { @MainActor in
                            store.toggleLock(projectId: project.id, username: LocalUser.shared.username)
                        }
                    }
                )) {
                    Text(project.isLocked ? "Locked" : "Unlocked")
                }
                .toggleStyle(.switch)
                .labelsHidden()
            }

            Text("Working Copy: \(project.workingCopyPath)")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 10) {
                Button {
                    store.openWorkingCopyInLogic(project: project)
                } label: {
                    Label("Open working version", systemImage: "music.note")
                }

                Button {
                    guard let v = selectedVersion else { return }
                    Task {
                        await store.addVersionIntoWorkingCopy(
                            projectId: project.id,
                            fromVersion: v,
                            currentUserId: auth.me?.id,
                            currentUserName: meName
                        )
                    }
                } label: {
                    Label("Merge", systemImage: "arrow.triangle.merge")
                }
                .disabled(selectedVersion == nil)
            }

            Text("Merges the selected version with your current working copy.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                TextField("Version note (e.g., “vocal comp cleanup”)", text: $versionMessage)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 520)

                Button("Create Version") {
                    let msg = versionMessage.trimmingCharacters(in: .whitespacesAndNewlines)
                    let final = msg.isEmpty ? "Update" : msg
                    versionMessage = ""
                    Task {
                        await store.createVersionFromWorkingCopy(
                            projectId: project.id,
                            message: final,
                            currentUserId: auth.me?.id,
                            currentUserName: meName
                        )
                    }
                }
                .disabled(project.isLocked && project.lockedBy != LocalUser.shared.username)
            }
        }
    }

    // MARK: - Versions list (shows uploader)

    private func versionsPanel(versions: [ProjectVersion]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Versions").font(.headline)

            List(versions, selection: $selectedVersionId) { v in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(v.message).font(.subheadline).bold()
                        Spacer()
                        Button {
                            store.openVersionCheckoutInLogic(project: project, version: v)
                        } label: {
                            Label("View this version", systemImage: "arrow.up.right.square")
                        }
                        .buttonStyle(.link)

                        Button {
                            Task {
                                await store.revertWorkingCopy(
                                    to: v,
                                    projectId: project.id,
                                    currentUserId: auth.me?.id,
                                    currentUserName: meName
                                )
                            }
                        } label: {
                            Label("Revert", systemImage: "arrow.uturn.backward")
                        }
                        .buttonStyle(.link)
                    }

                    HStack(spacing: 8) {
                        Text(v.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let who = v.createdByName, !who.isEmpty {
                            Text("• \(who)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text("\(v.manifest.count) files")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            .listStyle(.inset)

            Spacer()
        }
    }

    // MARK: - Files panel

    private func filesPanel(version: ProjectVersion?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Files").font(.headline)
                Spacer()
                TextField("Search files", text: $fileSearch)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
            }

            if let version {
                let filtered = version.manifest.filter {
                    fileSearch.isEmpty ? true : $0.relativePath.localizedCaseInsensitiveContains(fileSearch)
                }

                Table(filtered) {
                    TableColumn("Path") { entry in
                        Text(entry.relativePath).lineLimit(1)
                    }
                    TableColumn("Size") { entry in
                        Text(ByteCountFormatter.string(fromByteCount: entry.sizeBytes, countStyle: .file))
                            .monospacedDigit()
                    }
                    TableColumn("Modified") { entry in
                        Text(entry.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                            .monospacedDigit()
                    }
                    TableColumn("SHA-256") { entry in
                        Text(entry.sha256.prefix(12) + "…")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                ContentUnavailableView(
                    "No versions yet",
                    systemImage: "clock.badge.questionmark",
                    description: Text("Create your first version from the working copy.")
                )
            }

            Spacer()
        }
    }

    // MARK: - Share Sheet

    private var shareSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Share “\(project.name)”").font(.title3).bold()
                Spacer()
                Button("Done") { showingShareSheet = false }
            }

            Text("Owner can add/remove members per project.")
                .foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Members").font(.headline)

                if project.members.isEmpty {
                    Text("No members yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(project.members) { m in
                        HStack {
                            Text(m.userIdentifier)
                            Spacer()
                            Text(m.role.rawValue.capitalized)
                                .foregroundStyle(.secondary)

                            if isOwner && m.role != .owner {
                                Button(role: .destructive) {
                                    store.removeMember(projectId: project.id, memberId: m.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Add member").font(.headline)

                HStack(spacing: 10) {
                    TextField("Email/username", text: $newMemberId)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 320)

                    Picker("Role", selection: $newMemberRole) {
                        Text("Editor").tag(ProjectRole.editor)
                        Text("Viewer").tag(ProjectRole.viewer)
                    }
                    .frame(width: 140)

                    Button {
                        let trimmed = newMemberId.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        store.addMember(projectId: project.id, userIdentifier: trimmed, role: newMemberRole)
                        newMemberId = ""
                    } label: {
                        Label("Add", systemImage: "plus.circle")
                    }
                    .disabled(!isOwner)
                }
            }

            Spacer()
        }
        .padding(16)
        .frame(width: 560, height: 420)
    }

}

final class LocalUser {
    static let shared = LocalUser()
    var username: String = NSFullUserName().isEmpty ? "You" : NSFullUserName()
}
