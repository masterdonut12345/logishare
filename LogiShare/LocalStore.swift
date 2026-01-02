import Foundation
import Combine
import AppKit

@MainActor
final class LocalStore: ObservableObject {
    @Published var projects: [Project] = []
    @Published var activity: [ActivityEvent] = []
    @Published var selectedProjectId: UUID? = nil
    @Published var statusMessage: String? = nil

    private let persistence = LocalPersistence()

    init() { load() }

    func load() {
        do {
            let snapshot = try persistence.loadSnapshot()
            self.projects = snapshot.projects
            self.activity = snapshot.activity.sorted(by: { $0.date > $1.date })
        } catch {
            self.projects = []
            self.activity = []
            self.statusMessage = "Failed to load local data: \(error.localizedDescription)"
        }
    }

    func save() {
        do {
            try persistence.saveSnapshot(LocalSnapshot(projects: projects, activity: activity))
        } catch {
            self.statusMessage = "Failed to save: \(error.localizedDescription)"
        }
    }

    // MARK: - Security scope for initial import only
    func startAccessingPickedURL(_ pickedURL: URL) -> Bool {
        pickedURL.startAccessingSecurityScopedResource()
    }

    // MARK: - Paths

    private func workingCopyURL(projectId: UUID, projectName: String) throws -> URL {
        let base = persistence.workingDir.appendingPathComponent(projectId.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("\(projectName).logicx", isDirectory: true)
    }

    private func versionSnapshotURL(projectId: UUID, versionId: UUID, projectName: String) throws -> URL {
        let base = persistence.versionsDir
            .appendingPathComponent(projectId.uuidString, isDirectory: true)
            .appendingPathComponent(versionId.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("\(projectName).logicx", isDirectory: true)
    }

    private func checkoutURL(projectId: UUID, versionId: UUID, projectName: String) throws -> URL {
        let base = persistence.checkoutsDir
            .appendingPathComponent(projectId.uuidString, isDirectory: true)
            .appendingPathComponent(versionId.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("\(projectName).logicx", isDirectory: true)
    }

    private func replaceDirectory(at dst: URL, from src: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: dst.path) {
            try fm.removeItem(at: dst)
        }
        try fm.copyItem(at: src, to: dst)
    }

    // MARK: - Import / Versioning

    /// Import:
    /// - creates WORKING COPY (editable)
    /// - creates initial immutable VERSION SNAPSHOT from working copy
    func addProject(from pickedURL: URL, currentUserId: String?, currentUserName: String?) async {
        let name = pickedURL.deletingPathExtension().lastPathComponent
        let ok = startAccessingPickedURL(pickedURL)
        defer { if ok { pickedURL.stopAccessingSecurityScopedResource() } }

        do {
            statusMessage = "Importing \(name)…"

            let bookmark = try pickedURL.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )

            let projectId = UUID()

            let wcURL = try workingCopyURL(projectId: projectId, projectName: name)
            try replaceDirectory(at: wcURL, from: pickedURL)

            let manifest = try await ProjectScanner.scanLogicPackage(packageURL: wcURL)

            let versionId = UUID()
            let snapURL = try versionSnapshotURL(projectId: projectId, versionId: versionId, projectName: name)
            try replaceDirectory(at: snapURL, from: wcURL)

            let ownerName = (currentUserName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                ? currentUserName
                : "You"

            var project = Project(
                id: projectId,
                name: name,
                localPath: pickedURL.path,
                securityBookmark: bookmark,
                workingCopyPath: wcURL.path,
                ownerUserId: currentUserId,
                ownerDisplayName: ownerName,
                members: [ProjectMember(userIdentifier: ownerName ?? "You", role: .owner)]
            )
            project.updatedAt = Date()
            project.versions = [
                ProjectVersion(
                    id: versionId,
                    createdAt: Date(),
                    message: "Initial import",
                    manifest: manifest,
                    snapshotPath: snapURL.path,
                    createdByUserId: currentUserId,
                    createdByName: ownerName
                )
            ]

            projects.insert(project, at: 0)
            selectedProjectId = project.id
            activity.insert(ActivityEvent(title: "Imported project", detail: "\(name)", projectId: project.id), at: 0)

            statusMessage = "Import complete"
            save()
        } catch {
            statusMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    /// Create version from WORKING COPY (the editable one)
    func createVersionFromWorkingCopy(projectId: UUID,
                                     message: String,
                                     currentUserId: String?,
                                     currentUserName: String?) async {
        guard let idx = projects.firstIndex(where: { $0.id == projectId }) else { return }
        let project = projects[idx]

        do {
            statusMessage = "Creating version…"

            let wcURL = URL(fileURLWithPath: project.workingCopyPath)
            let manifest = try await ProjectScanner.scanLogicPackage(packageURL: wcURL)

            let versionId = UUID()
            let snapURL = try versionSnapshotURL(projectId: project.id, versionId: versionId, projectName: project.name)
            try replaceDirectory(at: snapURL, from: wcURL)

            let who = (currentUserName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                ? currentUserName
                : (project.ownerDisplayName ?? "You")

            var updated = project
            updated.updatedAt = Date()
            updated.versions.insert(
                ProjectVersion(
                    id: versionId,
                    createdAt: Date(),
                    message: message,
                    manifest: manifest,
                    snapshotPath: snapURL.path,
                    createdByUserId: currentUserId,
                    createdByName: who
                ),
                at: 0
            )

            projects[idx] = updated
            activity.insert(ActivityEvent(title: "Created version",
                                          detail: "\(updated.name) — \(message)",
                                          projectId: updated.id), at: 0)
            statusMessage = "Version created"
            save()
        } catch {
            statusMessage = "Version failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Opening in Logic

    /// Opens the WORKING copy for editing.
    func openWorkingCopyInLogic(project: Project) {
        let url = URL(fileURLWithPath: project.workingCopyPath)
        NSWorkspace.shared.open(url)
    }

    /// Opens a CHECKOUT copy of an old version so history stays immutable.
    func openVersionCheckoutInLogic(project: Project, version: ProjectVersion) {
        do {
            let src = URL(fileURLWithPath: version.snapshotPath)
            let dst = try checkoutURL(projectId: project.id, versionId: version.id, projectName: project.name)
            try replaceDirectory(at: dst, from: src)
            NSWorkspace.shared.open(dst)
        } catch {
            statusMessage = "Failed to open version: \(error.localizedDescription)"
        }
    }

    // MARK: - Forking (Make my own working copy)

    /// “Forks” a project (or a specific version) into a new project owned by the current user.
    /// Uses the chosen version snapshot as the starting point for the new working copy.
    func forkProject(sourceProject: Project,
                     fromVersion version: ProjectVersion,
                     newName: String?,
                     currentUserId: String?,
                     currentUserName: String?) async {
        do {
            let forkNameRaw = newName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let forkName = (forkNameRaw?.isEmpty == false) ? forkNameRaw! : "\(sourceProject.name) (Fork)"

            statusMessage = "Forking \(sourceProject.name)…"

            let newProjectId = UUID()
            let wcURL = try workingCopyURL(projectId: newProjectId, projectName: forkName)

            // working copy starts from the selected version snapshot
            let srcSnap = URL(fileURLWithPath: version.snapshotPath)
            try replaceDirectory(at: wcURL, from: srcSnap)

            let manifest = try await ProjectScanner.scanLogicPackage(packageURL: wcURL)

            let newVersionId = UUID()
            let snapURL = try versionSnapshotURL(projectId: newProjectId, versionId: newVersionId, projectName: forkName)
            try replaceDirectory(at: snapURL, from: wcURL)

            let ownerName = (currentUserName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                ? currentUserName
                : "You"

            var fork = Project(
                id: newProjectId,
                name: forkName,
                localPath: "(forked from \(sourceProject.name))",
                securityBookmark: nil,
                workingCopyPath: wcURL.path,
                ownerUserId: currentUserId,
                ownerDisplayName: ownerName,
                members: [ProjectMember(userIdentifier: ownerName ?? "You", role: .owner)]
            )
            fork.updatedAt = Date()
            fork.versions = [
                ProjectVersion(
                    id: newVersionId,
                    createdAt: Date(),
                    message: "Forked from \(sourceProject.name) — \(version.message)",
                    manifest: manifest,
                    snapshotPath: snapURL.path,
                    createdByUserId: currentUserId,
                    createdByName: ownerName
                )
            ]

            projects.insert(fork, at: 0)
            selectedProjectId = fork.id

            activity.insert(ActivityEvent(title: "Forked project",
                                          detail: "\(forkName)",
                                          projectId: fork.id), at: 0)

            statusMessage = "Fork created"
            save()
        } catch {
            statusMessage = "Fork failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Merge Projects (file-level merge into a new project)

    enum MergeConflictPolicy: String, CaseIterable {
        case keepA_renameB
        case keepB_renameA
    }

    /// Combine another saved version into the working copy so collaborators can add each other's changes.
    func addVersionIntoWorkingCopy(projectId: UUID,
                                   fromVersion: ProjectVersion,
                                   currentUserId: String?,
                                   currentUserName: String?) async {
        guard let idx = projects.firstIndex(where: { $0.id == projectId }) else { return }
        var project = projects[idx]
        let actor = (currentUserName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? currentUserName!
            : LocalUser.shared.username
        _ = currentUserId

        do {
            statusMessage = "Adding version to working copy…"

            let wcURL = URL(fileURLWithPath: project.workingCopyPath)
            let fromURL = URL(fileURLWithPath: fromVersion.snapshotPath)

            // Keep existing working copy files; rename incoming conflicts.
            try mergeDirectoryContents(
                base: wcURL,
                overlay: fromURL,
                policy: .keepA_renameB,
                incomingSuffix: "__fromVersion"
            )

            // Refresh manifest to validate package after the merge; history stays immutable.
            _ = try await ProjectScanner.scanLogicPackage(packageURL: wcURL)
            project.updatedAt = Date()

            projects[idx] = project
            activity.insert(
                ActivityEvent(
                    title: "Added version to working copy",
                    detail: "\(project.name) ← \(fromVersion.message) (by \(actor))",
                    projectId: project.id
                ),
                at: 0
            )

            statusMessage = "Version added to working copy"
            save()
        } catch {
            statusMessage = "Add failed: \(error.localizedDescription)"
        }
    }

    func mergeProjects(projectA: Project,
                       versionA: ProjectVersion,
                       projectB: Project,
                       versionB: ProjectVersion,
                       mergedName: String,
                       policy: MergeConflictPolicy,
                       currentUserId: String?,
                       currentUserName: String?) async {
        do {
            statusMessage = "Merging projects…"

            let newProjectId = UUID()
            let wcURL = try workingCopyURL(projectId: newProjectId, projectName: mergedName)
            try FileManager.default.createDirectory(at: wcURL.deletingLastPathComponent(), withIntermediateDirectories: true)

            // Start from A snapshot as the base
            let aSnap = URL(fileURLWithPath: versionA.snapshotPath)
            try replaceDirectory(at: wcURL, from: aSnap)

            // Then overlay/merge in B snapshot
            let bSnap = URL(fileURLWithPath: versionB.snapshotPath)
            try mergeDirectoryContents(base: wcURL, overlay: bSnap, policy: policy)

            let manifest = try await ProjectScanner.scanLogicPackage(packageURL: wcURL)

            let newVersionId = UUID()
            let snapURL = try versionSnapshotURL(projectId: newProjectId, versionId: newVersionId, projectName: mergedName)
            try replaceDirectory(at: snapURL, from: wcURL)

            let ownerName = (currentUserName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                ? currentUserName
                : "You"

            var merged = Project(
                id: newProjectId,
                name: mergedName,
                localPath: "(merged: \(projectA.name) + \(projectB.name))",
                securityBookmark: nil,
                workingCopyPath: wcURL.path,
                ownerUserId: currentUserId,
                ownerDisplayName: ownerName,
                members: [ProjectMember(userIdentifier: ownerName ?? "You", role: .owner)]
            )
            merged.updatedAt = Date()
            merged.versions = [
                ProjectVersion(
                    id: newVersionId,
                    createdAt: Date(),
                    message: "Merged \(projectA.name) + \(projectB.name)",
                    manifest: manifest,
                    snapshotPath: snapURL.path,
                    createdByUserId: currentUserId,
                    createdByName: ownerName
                )
            ]

            projects.insert(merged, at: 0)
            selectedProjectId = merged.id
            activity.insert(ActivityEvent(title: "Merged projects",
                                          detail: "\(mergedName)",
                                          projectId: merged.id), at: 0)

            statusMessage = "Merge complete"
            save()
        } catch {
            statusMessage = "Merge failed: \(error.localizedDescription)"
        }
    }

    /// File-level merge: copies overlay contents into base. On conflicts, renames one side.
    private func mergeDirectoryContents(base: URL,
                                        overlay: URL,
                                        policy: MergeConflictPolicy,
                                        incomingSuffix: String = "__fromB",
                                        existingSuffix: String = "__fromA") throws {
        let fm = FileManager.default
        let enumerator = fm.enumerator(at: overlay, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles], errorHandler: { _, _ in true })
        while let item = enumerator?.nextObject() as? URL {
            let rel = item.path.replacingOccurrences(of: overlay.path + "/", with: "")
            let dest = base.appendingPathComponent(rel, isDirectory: false)

            let rv = try item.resourceValues(forKeys: [.isDirectoryKey])
            if rv.isDirectory == true {
                if !fm.fileExists(atPath: dest.path) {
                    try fm.createDirectory(at: dest, withIntermediateDirectories: true)
                }
                continue
            }

            if fm.fileExists(atPath: dest.path) {
                // conflict: rename one side
                switch policy {
                case .keepA_renameB:
                    let renamed = dest.deletingLastPathComponent()
                        .appendingPathComponent(dest.deletingPathExtension().lastPathComponent + incomingSuffix + "." + dest.pathExtension)
                    try fm.copyItem(at: item, to: renamed)
                case .keepB_renameA:
                    // rename existing A file, then copy B into original dest
                    let renamedA = dest.deletingLastPathComponent()
                        .appendingPathComponent(dest.deletingPathExtension().lastPathComponent + existingSuffix + "." + dest.pathExtension)
                    if fm.fileExists(atPath: renamedA.path) { try? fm.removeItem(at: renamedA) }
                    try fm.moveItem(at: dest, to: renamedA)
                    try fm.copyItem(at: item, to: dest)
                }
            } else {
                try fm.copyItem(at: item, to: dest)
            }
        }
    }

    // MARK: - Sharing (owner can add/remove members)

    func addMember(projectId: UUID, userIdentifier: String, role: ProjectRole) {
        guard let idx = projects.firstIndex(where: { $0.id == projectId }) else { return }
        var p = projects[idx]
        let trimmed = userIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if p.members.contains(where: { $0.userIdentifier.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            statusMessage = "Member already added"
            return
        }

        p.members.append(ProjectMember(userIdentifier: trimmed, role: role))
        p.updatedAt = Date()
        projects[idx] = p

        activity.insert(ActivityEvent(title: "Added member", detail: "\(trimmed) → \(p.name)", projectId: projectId), at: 0)
        save()
    }

    func removeMember(projectId: UUID, memberId: UUID) {
        guard let idx = projects.firstIndex(where: { $0.id == projectId }) else { return }
        var p = projects[idx]
        p.members.removeAll { $0.id == memberId }
        p.updatedAt = Date()
        projects[idx] = p
        activity.insert(ActivityEvent(title: "Removed member", detail: "\(p.name)", projectId: projectId), at: 0)
        save()
    }

    // MARK: - Basic project utilities

    func toggleLock(projectId: UUID, username: String) {
        guard let idx = projects.firstIndex(where: { $0.id == projectId }) else { return }
        var p = projects[idx]
        p.isLocked.toggle()
        p.lockedBy = p.isLocked ? username : nil
        p.updatedAt = Date()
        projects[idx] = p
        activity.insert(ActivityEvent(title: p.isLocked ? "Locked project" : "Unlocked project",
                                      detail: "\(p.name)" + (p.isLocked ? " (by \(username))" : ""),
                                      projectId: projectId), at: 0)
        save()
    }

    func removeProject(projectId: UUID) {
        projects.removeAll { $0.id == projectId }
        if selectedProjectId == projectId { selectedProjectId = projects.first?.id }
        activity.insert(ActivityEvent(title: "Removed project", detail: nil, projectId: nil), at: 0)
        save()
    }
}

// MARK: - Persistence

struct LocalSnapshot: Codable {
    var projects: [Project]
    var activity: [ActivityEvent]
}

final class LocalPersistence {
    private let fm = FileManager.default

    var appSupportDir: URL {
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("LogicShare", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    var workingDir: URL {
        let dir = appSupportDir.appendingPathComponent("working", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    var versionsDir: URL {
        let dir = appSupportDir.appendingPathComponent("versions", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    var checkoutsDir: URL {
        let dir = appSupportDir.appendingPathComponent("checkouts", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private var snapshotURL: URL {
        appSupportDir.appendingPathComponent("snapshot.json")
    }

    func loadSnapshot() throws -> LocalSnapshot {
        if !fm.fileExists(atPath: snapshotURL.path) {
            return LocalSnapshot(projects: [], activity: [])
        }
        let data = try Data(contentsOf: snapshotURL)
        return try JSONDecoder.withISO8601.decode(LocalSnapshot.self, from: data)
    }

    func saveSnapshot(_ snapshot: LocalSnapshot) throws {
        let data = try JSONEncoder.withISO8601.encode(snapshot)
        try data.write(to: snapshotURL, options: [.atomic])
    }
}

extension JSONEncoder {
    static var withISO8601: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }
}
extension JSONDecoder {
    static var withISO8601: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
