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
    @State private var showingForkSheet = false
    @State private var showingMergeSheet = false

    // Share form
    @State private var newMemberId: String = ""
    @State private var newMemberRole: ProjectRole = .editor

    // Fork form
    @State private var forkName: String = ""

    // Merge form
    @State private var mergeName: String = ""
    @State private var mergeOtherProjectId: UUID?
    @State private var mergeOtherVersionId: UUID?
    @State private var mergePolicy: LocalStore.MergeConflictPolicy = .keepA_renameB

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
            if mergeName.isEmpty { mergeName = "\(project.name) (Merged)" }
            if forkName.isEmpty { forkName = "\(project.name) (Fork)" }
            if mergeOtherProjectId == nil { mergeOtherProjectId = project.id }
            if mergeOtherVersionId == nil {
                mergeOtherVersionId = defaultMergeVersionId(
                    in: project,
                    excluding: selectedVersion
                )
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Button("Share…") { showingShareSheet = true }
                        .disabled(!isOwner)

                    Divider()

                    Button("Fork selected version…") { showingForkSheet = true }
                        .disabled(selectedVersion == nil)

                    Divider()

                    Button("Merge with another project…") { showingMergeSheet = true }
                        .disabled(store.projects.count < 2 || selectedVersion == nil)
                } label: {
                    Label("Actions", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            shareSheet
        }
        .sheet(isPresented: $showingForkSheet) {
            forkSheet(selectedVersion: selectedVersion)
        }
        .sheet(isPresented: $showingMergeSheet) {
            mergeSheet(selectedVersion: selectedVersion)
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
                    Label("Open Working Copy in Logic", systemImage: "music.note")
                }

                Button {
                    if let v = selectedVersion {
                        store.openVersionCheckoutInLogic(project: project, version: v)
                    }
                } label: {
                    Label("Open Selected Version (Checkout)", systemImage: "clock.arrow.circlepath")
                }
                .disabled(selectedVersion == nil)

                Spacer()
            }

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
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(v.message).font(.subheadline).bold()
                        Spacer()
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

    // MARK: - Fork Sheet

    private func forkSheet(selectedVersion: ProjectVersion?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Fork Project").font(.title3).bold()
                Spacer()
                Button("Done") { showingForkSheet = false }
            }

            Text("This creates a new project you own, with its own working copy.")
                .foregroundStyle(.secondary)

            Divider()

            TextField("New project name", text: $forkName)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 420)

            Button {
                guard let v = selectedVersion else { return }
                Task {
                    await store.forkProject(
                        sourceProject: project,
                        fromVersion: v,
                        newName: forkName,
                        currentUserId: auth.me?.id,
                        currentUserName: meName
                    )
                    showingForkSheet = false
                }
            } label: {
                Label("Create Fork", systemImage: "point.filled.topleft.down.curvedto.point.bottomright.up")
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedVersion == nil)

            Spacer()
        }
        .padding(16)
        .frame(width: 520, height: 240)
    }

    // MARK: - Merge Sheet

    private func mergeSheet(selectedVersion: ProjectVersion?) -> some View {
        let targetProject = store.projects.first(where: { $0.id == (mergeOtherProjectId ?? project.id) }) ?? project
        let mergeableVersions = mergeCandidates(
            in: targetProject,
            excluding: targetProject.id == project.id ? selectedVersion : nil
        )
        let selectedOtherVersion = mergeableVersions.first(where: { $0.id == mergeOtherVersionId }) ?? mergeableVersions.first

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Merge Projects").font(.title3).bold()
                Spacer()
                Button("Done") { showingMergeSheet = false }
            }

            Text("Combine two versions without overwriting work — great when one person adds piano and another adds guitar.")
                .foregroundStyle(.secondary)

            Text("This is a file-level merge of the .logicx packages (not a Logic-aware track merge).")
                .foregroundStyle(.secondary)

            Divider()

            TextField("New merged project name", text: $mergeName)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 420)

            Picker("Merge with", selection: $mergeOtherProjectId) {
                Text("This project (choose another version)").tag(UUID?.some(project.id))
                ForEach(store.projects.filter({ $0.id != project.id }), id: \.id) { p in
                    Text(p.name).tag(UUID?.some(p.id))
                }
            }
            .frame(maxWidth: 420)
            .onChange(of: mergeOtherProjectId) { newValue in
                if let projectId = newValue, let newProject = store.projects.first(where: { $0.id == projectId }) {
                    mergeOtherVersionId = defaultMergeVersionId(
                        in: newProject,
                        excluding: (newProject.id == project.id) ? selectedVersion : nil
                    )
                }
            }

            if mergeableVersions.isEmpty {
                Text("No other versions available to merge.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Use version", selection: $mergeOtherVersionId) {
                    ForEach(mergeableVersions, id: \.id) { version in
                        Text(versionLabel(version))
                            .tag(UUID?.some(version.id))
                    }
                }
                .frame(maxWidth: 420)
            }

            Picker("Conflict policy", selection: $mergePolicy) {
                Text("Keep A, rename B").tag(LocalStore.MergeConflictPolicy.keepA_renameB)
                Text("Keep B, rename A").tag(LocalStore.MergeConflictPolicy.keepB_renameA)
            }
            .frame(maxWidth: 420)

            Button {
                guard
                    let vA = selectedVersion,
                    let otherId = mergeOtherProjectId,
                    let otherProject = store.projects.first(where: { $0.id == otherId }),
                    let vB = otherProject.versions.first(where: { $0.id == (mergeOtherVersionId ?? $0.id) })
                else { return }

                Task {
                    await store.mergeProjects(
                        projectA: project,
                        versionA: vA,
                        projectB: otherProject,
                        versionB: vB,
                        mergedName: mergeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "\(project.name) (Merged)" : mergeName,
                        policy: mergePolicy,
                        currentUserId: auth.me?.id,
                        currentUserName: meName
                    )
                    showingMergeSheet = false
                }
            } label: {
                Label("Create Merged Project", systemImage: "arrow.triangle.merge")
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedVersion == nil || mergeOtherProjectId == nil || selectedOtherVersion == nil)

            Text("Note: merges the selected version of this project with the chosen version from the other project.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(16)
        .frame(width: 560, height: 360)
    }

    private func mergeCandidates(in project: Project, excluding version: ProjectVersion?) -> [ProjectVersion] {
        project.versions.filter { v in
            guard let excluded = version else { return true }
            return v.id != excluded.id
        }
    }

    private func defaultMergeVersionId(in project: Project, excluding version: ProjectVersion?) -> UUID? {
        mergeCandidates(in: project, excluding: version).first?.id
    }

    private func versionLabel(_ version: ProjectVersion) -> String {
        let dateString = version.createdAt.formatted(date: .abbreviated, time: .shortened)
        return "\(version.message) — \(dateString)"
    }
}

final class LocalUser {
    static let shared = LocalUser()
    var username: String = NSFullUserName().isEmpty ? "You" : NSFullUserName()
}
