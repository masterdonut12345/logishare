import Foundation

enum SidebarTab: String, CaseIterable, Identifiable {
    case projects = "Projects"
    case activity = "Activity"
    case people = "People"
    case account = "Account"
    var id: String { rawValue }
}

enum ProjectRole: String, Codable, CaseIterable {
    case owner
    case editor
    case viewer
}

struct ProjectMember: Codable, Identifiable, Hashable {
    var id: UUID
    var userIdentifier: String   // email/username for now
    var role: ProjectRole

    init(id: UUID = UUID(), userIdentifier: String, role: ProjectRole) {
        self.id = id
        self.userIdentifier = userIdentifier
        self.role = role
    }
}

struct Project: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String

    // informational (where the initial import came from)
    var localPath: String
    var securityBookmark: Data?

    // editable copy in Application Support
    var workingCopyPath: String

    // ownership + members
    var ownerUserId: String?
    var ownerDisplayName: String?
    var members: [ProjectMember]

    var createdAt: Date
    var updatedAt: Date
    var isLocked: Bool
    var lockedBy: String?

    // newest first
    var versions: [ProjectVersion]

    init(
        id: UUID = UUID(),
        name: String,
        localPath: String,
        securityBookmark: Data? = nil,
        workingCopyPath: String,
        ownerUserId: String? = nil,
        ownerDisplayName: String? = nil,
        members: [ProjectMember] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isLocked: Bool = false,
        lockedBy: String? = nil,
        versions: [ProjectVersion] = []
    ) {
        self.id = id
        self.name = name
        self.localPath = localPath
        self.securityBookmark = securityBookmark
        self.workingCopyPath = workingCopyPath
        self.ownerUserId = ownerUserId
        self.ownerDisplayName = ownerDisplayName
        self.members = members
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isLocked = isLocked
        self.lockedBy = lockedBy
        self.versions = versions
    }
}

struct ProjectVersion: Codable, Identifiable, Hashable {
    var id: UUID
    var createdAt: Date
    var message: String
    var manifest: [FileEntry]

    // immutable snapshot
    var snapshotPath: String

    // who created/uploaded this version
    var createdByUserId: String?
    var createdByName: String?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        message: String,
        manifest: [FileEntry],
        snapshotPath: String,
        createdByUserId: String? = nil,
        createdByName: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.message = message
        self.manifest = manifest
        self.snapshotPath = snapshotPath
        self.createdByUserId = createdByUserId
        self.createdByName = createdByName
    }
}

struct FileEntry: Codable, Identifiable, Hashable {
    var id: UUID
    var relativePath: String
    var sizeBytes: Int64
    var modifiedAt: Date
    var sha256: String

    init(id: UUID = UUID(),
         relativePath: String,
         sizeBytes: Int64,
         modifiedAt: Date,
         sha256: String) {
        self.id = id
        self.relativePath = relativePath
        self.sizeBytes = sizeBytes
        self.modifiedAt = modifiedAt
        self.sha256 = sha256
    }
}

struct ActivityEvent: Codable, Identifiable, Hashable {
    var id: UUID
    var date: Date
    var title: String
    var detail: String?
    var projectId: UUID?

    init(id: UUID = UUID(), date: Date = Date(), title: String, detail: String? = nil, projectId: UUID? = nil) {
        self.id = id
        self.date = date
        self.title = title
        self.detail = detail
        self.projectId = projectId
    }
}

struct Person: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var role: String
}

