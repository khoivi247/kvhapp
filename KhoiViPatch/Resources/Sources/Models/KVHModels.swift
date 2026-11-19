import Foundation

// MARK: - .kvh Patch Specification (KhoiViDev Hybrid Package)

struct KVHManifest: Codable, Identifiable {
    var id: String { patchId }
    let formatVersion: String
    let patchId: String
    let name: String
    let version: String
    let author: String
    let description: String
    let targetBundleId: String
    let targetAppGroup: String?
    let minOS: String?
    let maxOS: String?
    let passwordSHA256: String?
    let operations: [KVHOperation]
    let createdAt: String

    static func template(
        name: String,
        targetBundleId: String,
        description: String,
        operations: [KVHOperation],
        passwordSHA256: String? = nil
    ) -> KVHManifest {
        let formatter = ISO8601DateFormatter()
        return KVHManifest(
            formatVersion: "1.0",
            patchId: "kvh.\(UUID().uuidString.prefix(8).lowercased())",
            name: name,
            version: "1.0.0",
            author: "KhoiViDev",
            description: description,
            targetBundleId: targetBundleId,
            targetAppGroup: nil,
            minOS: "15.0",
            maxOS: nil,
            passwordSHA256: passwordSHA256,
            operations: operations,
            createdAt: formatter.string(from: Date())
        )
    }
}

enum KVHOperationType: String, Codable, CaseIterable {
    case replace = "replace"
    case mergePlist = "merge_plist"
    case mergeJSON = "merge_json"
    case delete = "delete"
    case createDirectory = "mkdir"
}

struct KVHOperation: Codable, Identifiable, Hashable {
    let id: String
    let type: KVHOperationType
    /// Path inside the .kvh archive (e.g. "Application/Documents/config.plist")
    let sourcePath: String?
    /// Relative path inside the target app container (e.g. "Documents/config.plist")
    let targetRelativePath: String
    let sha256: String?
}

struct LoadedKVHPackage: Identifiable {
    let id = UUID()
    let fileURL: URL
    let fileName: String
    let manifest: KVHManifest
    let entries: [String: Data]
    let fileSizeBytes: Int64

    var isPasswordProtected: Bool {
        guard let hash = manifest.passwordSHA256 else { return false }
        return !hash.isEmpty
    }

    var payloadEntriesCount: Int {
        entries.keys.filter { $0 != "settings.json" && !$0.hasSuffix("/") }.count
    }
}

// MARK: - Container & File Browser Models

enum ContainerAccessMode: String, CaseIterable, Identifiable {
    case sandboxWorkspace = "Sandbox & Workspaces (Standard iOS)"
    case mobileHouseArrest = "MobileHouseArrest / Exploit Bridge"

    var id: String { rawValue }
}

struct AppContainerInfo: Identifiable, Hashable {
    let id: String // bundleId
    let name: String
    let bundleId: String
    let version: String
    let rootURL: URL
    let isSystemOrPrivileged: Bool
    let isFavorite: Bool
    let descriptionNote: String
}

struct ContainerFileItem: Identifiable, Hashable {
    let id: String
    let name: String
    let url: URL
    let relativePath: String
    let isDirectory: Bool
    let sizeBytes: Int64
    let modifiedDate: Date

    var fileExtension: String {
        url.pathExtension.lowercased()
    }

    var isPlistOrJSON: Bool {
        fileExtension == "plist" || fileExtension == "json"
    }
}

// MARK: - Backup & Restore

struct KVHBackupRecord: Codable, Identifiable {
    let id: String
    let patchName: String
    let targetBundleId: String
    let createdAt: Date
    let backupFolderName: String
    let backedUpFiles: [String]
}

// MARK: - Cleaner Models

struct CleanableTarget: Identifiable {
    let id = UUID()
    let title: String
    let bundleId: String
    let pathURL: URL
    let reclaimableBytes: Int64
    let fileCount: Int
    var isSelected: Bool = true
}

// MARK: - Marketplace / Repo Models (repo.json)

struct KVHRepoManifest: Codable {
    let repoName: String
    let repoAuthor: String
    let description: String?
    let packages: [KVHRepoPackage]
}

struct KVHRepoPackage: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let version: String
    let author: String
    let targetBundleId: String
    let summary: String
    let downloadURL: String
    let sha256: String?
    let category: String
}
