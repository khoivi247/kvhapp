import Foundation
import CryptoKit

enum KVHError: LocalizedError {
    case missingManifest
    case invalidManifest(String)
    case wrongPassword
    case targetContainerNotAccessible(String)
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingManifest:
            return "Gói .kvh thiếu tệp cấu hình settings.json."
        case .invalidManifest(let detail):
            return "Lỗi đọc settings.json: \(detail)"
        case .wrongPassword:
            return "Mật khẩu mở khóa tệp .kvh không chính xác."
        case .targetContainerNotAccessible(let bundleId):
            return "Không có quyền truy cập container của \(bundleId) trên phiên bản iOS hoặc chế độ hiện tại."
        case .operationFailed(let reason):
            return "Áp dụng patch thất bại: \(reason)"
        }
    }
}

final class KVHArchiveEngine {
    static let shared = KVHArchiveEngine()

    private let fm = FileManager.default
    private let backupsIndexFileName = "kvh_backups_index.json"

    var patchesDirectory: URL {
        let dir = documentsDirectory.appendingPathComponent("KVHPatches", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    var backupsDirectory: URL {
        let dir = documentsDirectory.appendingPathComponent("KVHBackups", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var documentsDirectory: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    // MARK: - Load & Inspect .kvh

    func loadPackage(from url: URL) throws -> LoadedKVHPackage {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        let entries = try MiniZipArchive.readEntries(from: data)

        guard let settingsData = entries["settings.json"] else {
            throw KVHError.missingManifest
        }

        let manifest: KVHManifest
        do {
            manifest = try JSONDecoder().decode(KVHManifest.self, from: settingsData)
        } catch {
            throw KVHError.invalidManifest(error.localizedDescription)
        }

        let attrs = try? fm.attributesOfItem(atPath: url.path)
        let fileSize = (attrs?[.size] as? Int64) ?? Int64(data.count)

        return LoadedKVHPackage(
            fileURL: url,
            fileName: url.lastPathComponent,
            manifest: manifest,
            entries: entries,
            fileSizeBytes: fileSize
        )
    }

    func importKVHFile(from externalURL: URL) throws -> LoadedKVHPackage {
        let accessed = externalURL.startAccessingSecurityScopedResource()
        defer { if accessed { externalURL.stopAccessingSecurityScopedResource() } }

        let destination = patchesDirectory.appendingPathComponent(externalURL.lastPathComponent)
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.copyItem(at: externalURL, to: destination)
        return try loadPackage(from: destination)
    }

    func listSavedPatches() -> [LoadedKVHPackage] {
        guard let urls = try? fm.contentsOfDirectory(at: patchesDirectory, includingPropertiesForKeys: nil) else {
            return []
        }
        return urls
            .filter { $0.pathExtension.lowercased() == "kvh" }
            .compactMap { try? loadPackage(from: $0) }
            .sorted { $0.fileName < $1.fileName }
    }

    // MARK: - Create .kvh Package

    func createPackage(
        name: String,
        targetBundleId: String,
        description: String,
        password: String?,
        sourceFiles: [(relativeTargetPath: String, data: Data)]
    ) throws -> URL {
        var entries: [String: Data] = [:]
        var ops: [KVHOperation] = []

        for item in sourceFiles {
            let cleanRel = item.relativeTargetPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let archivePath = "Application/\(cleanRel)"
            entries[archivePath] = item.data

            let hash = sha256Hex(item.data)
            let opType: KVHOperationType = cleanRel.hasSuffix(".plist") ? .mergePlist : .replace

            ops.append(KVHOperation(
                id: UUID().uuidString,
                type: opType,
                sourcePath: archivePath,
                targetRelativePath: cleanRel,
                sha256: hash
            ))
        }

        let passwordHash: String? = {
            guard let pw = password, !pw.isEmpty else { return nil }
            return sha256Hex(Data(pw.utf8))
        }()

        let manifest = KVHManifest.template(
            name: name,
            targetBundleId: targetBundleId,
            description: description,
            operations: ops,
            passwordSHA256: passwordHash
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        entries["settings.json"] = try encoder.encode(manifest)

        let archiveData = MiniZipArchive.writeArchive(entries: entries)
        let safeFileName = name
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-")
        let outURL = patchesDirectory.appendingPathComponent("\(safeFileName).kvh")
        try archiveData.write(to: outURL, options: .atomic)
        return outURL
    }

    // MARK: - Apply & Backup

    func verifyPassword(_ password: String, for package: LoadedKVHPackage) -> Bool {
        guard let expected = package.manifest.passwordSHA256, !expected.isEmpty else {
            return true
        }
        return sha256Hex(Data(password.utf8)) == expected
    }

    func applyPackage(
        _ package: LoadedKVHPackage,
        password: String?,
        targetRootURL: URL
    ) throws -> KVHBackupRecord {
        if !verifyPassword(password ?? "", for: package) {
            throw KVHError.wrongPassword
        }

        // 1. Create pre-patch backup snapshot
        let backupId = UUID().uuidString.prefix(8).lowercased()
        let backupFolderName = "\(package.manifest.targetBundleId)_\(backupId)"
        let backupRoot = backupsDirectory.appendingPathComponent(backupFolderName, isDirectory: true)
        try fm.createDirectory(at: backupRoot, withIntermediateDirectories: true)

        var backedUpFiles: [String] = []

        for op in package.manifest.operations {
            let cleanTargetRel = op.targetRelativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let destURL = targetRootURL.appendingPathComponent(cleanTargetRel)

            // Backup existing file if present
            if fm.fileExists(atPath: destURL.path) {
                let backupFileURL = backupRoot.appendingPathComponent(cleanTargetRel)
                try fm.createDirectory(at: backupFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fm.fileExists(atPath: backupFileURL.path) {
                    try fm.removeItem(at: backupFileURL)
                }
                try fm.copyItem(at: destURL, to: backupFileURL)
                backedUpFiles.append(cleanTargetRel)
            }

            // Execute operation
            switch op.type {
            case .createDirectory:
                try fm.createDirectory(at: destURL, withIntermediateDirectories: true)

            case .delete:
                if fm.fileExists(atPath: destURL.path) {
                    try fm.removeItem(at: destURL)
                }

            case .replace:
                guard let src = op.sourcePath, let payload = package.entries[src] else {
                    throw KVHError.operationFailed("Thiếu dữ liệu nguồn \(op.sourcePath ?? "") trong gói .kvh")
                }
                try fm.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try payload.write(to: destURL, options: .atomic)

            case .mergePlist:
                guard let src = op.sourcePath, let payload = package.entries[src] else {
                    throw KVHError.operationFailed("Thiếu plist nguồn \(op.sourcePath ?? "")")
                }
                try fm.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                let merged = try PlistJsonEditorService.mergePlist(patchData: payload, intoExistingFileAt: destURL)
                try merged.write(to: destURL, options: .atomic)

            case .mergeJSON:
                guard let src = op.sourcePath, let payload = package.entries[src] else {
                    throw KVHError.operationFailed("Thiếu JSON nguồn \(op.sourcePath ?? "")")
                }
                try fm.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                let merged = try PlistJsonEditorService.mergeJSON(patchData: payload, intoExistingFileAt: destURL)
                try merged.write(to: destURL, options: .atomic)
            }
        }

        let record = KVHBackupRecord(
            id: String(backupId),
            patchName: package.manifest.name,
            targetBundleId: package.manifest.targetBundleId,
            createdAt: Date(),
            backupFolderName: backupFolderName,
            backedUpFiles: backedUpFiles
        )
        saveBackupRecord(record)
        return record
    }

    func restoreBackup(_ record: KVHBackupRecord, to targetRootURL: URL) throws {
        let backupRoot = backupsDirectory.appendingPathComponent(record.backupFolderName, isDirectory: true)
        for relPath in record.backedUpFiles {
            let src = backupRoot.appendingPathComponent(relPath)
            let dest = targetRootURL.appendingPathComponent(relPath)
            if fm.fileExists(atPath: src.path) {
                try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fm.fileExists(atPath: dest.path) {
                    try fm.removeItem(at: dest)
                }
                try fm.copyItem(at: src, to: dest)
            }
        }
    }

    func listBackups() -> [KVHBackupRecord] {
        let indexURL = backupsDirectory.appendingPathComponent(backupsIndexFileName)
        guard let data = try? Data(contentsOf: indexURL),
              let records = try? JSONDecoder().decode([KVHBackupRecord].self, from: data) else {
            return []
        }
        return records.sorted { $0.createdAt > $1.createdAt }
    }

    private func saveBackupRecord(_ record: KVHBackupRecord) {
        var current = listBackups()
        current.insert(record, at: 0)
        let indexURL = backupsDirectory.appendingPathComponent(backupsIndexFileName)
        if let data = try? JSONEncoder().encode(current) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }

    func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
