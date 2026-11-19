import Foundation
import UIKit

/// Manages app-data container discovery, local workspaces, favorites, and privileged bridge diagnostics.
final class ContainerAccessManager: ObservableObject {
    static let shared = ContainerAccessManager()

    @Published var accessMode: ContainerAccessMode = .sandboxWorkspace
    @Published var containers: [AppContainerInfo] = []
    @Published var favoritePaths: Set<String> = []

    private let fm = FileManager.default
    private let favoritesKey = "kvh_favorite_paths"
    private let customWorkspacesKey = "kvh_custom_workspaces"

    private init() {
        loadFavorites()
        seedDefaultWorkspaceIfNeeded()
        reloadContainers()
    }

    // MARK: - Diagnostics

    var currentBundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "unknown"
    }

    var currentIOSVersion: String {
        UIDevice.current.systemVersion
    }

    var isMobileHouseArrestBundleId: Bool {
        currentBundleIdentifier == "com.apple.mobile.MobileHouseArrest"
    }

    var hasSystemContainerAccess: Bool {
        // Real check: attempt to read /var/mobile/Library or system app containers directory.
        // On stock iOS without a matching kernel/sandbox exploit or privileged entitlement, this returns false.
        let testPath = "/var/mobile/Containers/Data/Application"
        return fm.isReadableFile(atPath: testPath)
    }

    // MARK: - Container Discovery

    func reloadContainers() {
        var list: [AppContainerInfo] = []

        // 1. Always expose KhoiViPatch's own app container
        if let appSupport = fm.urls(for: .libraryDirectory, in: .userDomainMask).first?.deletingLastPathComponent() {
            list.append(AppContainerInfo(
                id: currentBundleIdentifier,
                name: "KhoiViPatch (App Container)",
                bundleId: currentBundleIdentifier,
                version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0",
                rootURL: appSupport,
                isSystemOrPrivileged: false,
                isFavorite: true,
                descriptionNote: "Container thực của KhoiViPatch — hỗ trợ đọc/ghi, tạo .kvh & test patch trực tiếp"
            ))
        }

        // 2. Local App Workspaces inside Documents/Workspaces (mirroring BundleID structure for .kvh creation/testing)
        let workspacesDir = workspacesRootDirectory
        if let subdirs = try? fm.contentsOfDirectory(at: workspacesDir, includingPropertiesForKeys: nil) {
            for dir in subdirs where hasDirectoryFlag(dir) {
                let bundleId = dir.lastPathComponent
                list.append(AppContainerInfo(
                    id: bundleId,
                    name: friendlyName(for: bundleId),
                    bundleId: bundleId,
                    version: "Workspace",
                    rootURL: dir,
                    isSystemOrPrivileged: false,
                    isFavorite: favoritePaths.contains(dir.path),
                    descriptionNote: "Workspace cục bộ theo Bundle ID — dùng để duyệt file, chỉnh plist và đóng gói .kvh"
                ))
            }
        }

        // 3. Privileged / System containers if exploit/entitlement access is actually granted
        if accessMode == .mobileHouseArrest && hasSystemContainerAccess {
            let systemAppsRoot = URL(fileURLWithPath: "/var/mobile/Containers/Data/Application")
            if let uuidDirs = try? fm.contentsOfDirectory(at: systemAppsRoot, includingPropertiesForKeys: nil) {
                for uuidDir in uuidDirs {
                    let metaURL = uuidDir.appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
                    if let metaData = try? Data(contentsOf: metaURL),
                       let plist = try? PropertyListSerialization.propertyList(from: metaData, options: [], format: nil) as? [String: Any],
                       let bundleId = plist["MCMMetadataIdentifier"] as? String {
                        list.append(AppContainerInfo(
                            id: bundleId,
                            name: friendlyName(for: bundleId),
                            bundleId: bundleId,
                            version: "Container",
                            rootURL: uuidDir,
                            isSystemOrPrivileged: true,
                            isFavorite: favoritePaths.contains(uuidDir.path),
                            descriptionNote: "Container hệ thống (Đã ánh xạ UUID -> Bundle ID)"
                        ))
                    }
                }
            }
        }

        DispatchQueue.main.async {
            self.containers = list
        }
    }

    func createWorkspace(bundleId: String) throws -> URL {
        let clean = bundleId.trimmingCharacters(in: .whitespacesAndNewlines)
        let dir = workspacesRootDirectory.appendingPathComponent(clean, isDirectory: true)
        let docs = dir.appendingPathComponent("Documents", isDirectory: true)
        let prefs = dir.appendingPathComponent("Library/Preferences", isDirectory: true)
        let caches = dir.appendingPathComponent("Library/Caches", isDirectory: true)

        try fm.createDirectory(at: docs, withIntermediateDirectories: true)
        try fm.createDirectory(at: prefs, withIntermediateDirectories: true)
        try fm.createDirectory(at: caches, withIntermediateDirectories: true)

        reloadContainers()
        return dir
    }

    func resolveTargetContainerURL(for bundleId: String) -> URL? {
        if let match = containers.first(where: { $0.bundleId == bundleId }) {
            return match.rootURL
        }
        return nil
    }

    // MARK: - File Operations

    func listDirectory(at url: URL) -> [ContainerFileItem] {
        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: []
        ) else {
            return []
        }

        return contents.compactMap { itemURL -> ContainerFileItem? in
            let values = try? itemURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
            let isDir = values?.isDirectory ?? false
            let size = Int64(values?.fileSize ?? 0)
            let modDate = values?.contentModificationDate ?? Date()

            return ContainerFileItem(
                id: itemURL.path,
                name: itemURL.lastPathComponent,
                url: itemURL,
                relativePath: itemURL.lastPathComponent,
                isDirectory: isDir,
                sizeBytes: size,
                modifiedDate: modDate
            )
        }.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory && !b.isDirectory }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    func toggleFavorite(path: String) {
        if favoritePaths.contains(path) {
            favoritePaths.remove(path)
        } else {
            favoritePaths.insert(path)
        }
        UserDefaults.standard.set(Array(favoritePaths), forKey: favoritesKey)
        reloadContainers()
    }

    // MARK: - Private Helpers

    var workspacesRootDirectory: URL {
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("Workspaces", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func loadFavorites() {
        let saved = UserDefaults.standard.stringArray(forKey: favoritesKey) ?? []
        favoritePaths = Set(saved)
    }

    private func hasDirectoryFlag(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    private func friendlyName(for bundleId: String) -> String {
        bundleId.split(separator: ".").last.map(String.init)?.capitalized ?? bundleId
    }

    private func seedDefaultWorkspaceIfNeeded() {
        let demoWorkspace = workspacesRootDirectory.appendingPathComponent("com.khoividev.sandbox.demo", isDirectory: true)
        guard !fm.fileExists(atPath: demoWorkspace.path) else { return }

        let prefs = demoWorkspace.appendingPathComponent("Library/Preferences", isDirectory: true)
        let caches = demoWorkspace.appendingPathComponent("Library/Caches", isDirectory: true)
        let docs = demoWorkspace.appendingPathComponent("Documents", isDirectory: true)

        try? fm.createDirectory(at: prefs, withIntermediateDirectories: true)
        try? fm.createDirectory(at: caches, withIntermediateDirectories: true)
        try? fm.createDirectory(at: docs, withIntermediateDirectories: true)

        let samplePlist: [String: Any] = [
            "Author": "KhoiViDev",
            "Format": "kvh",
            "EnableHighFrameRate": true,
            "CustomTheme": "CyberCyan",
            "BuildTarget": "iOS"
        ]
        if let plistData = try? PropertyListSerialization.data(fromPropertyList: samplePlist, format: .xml, options: 0) {
            try? plistData.write(to: prefs.appendingPathComponent("com.khoividev.sandbox.demo.plist"))
        }

        let sampleJSON = """
        {
          "profile": "KhoiViDev Default",
          "patchExtension": ".kvh",
          "autoBackup": true
        }
        """
        try? sampleJSON.data(using: .utf8)?.write(to: docs.appendingPathComponent("config.json"))
    }
}
