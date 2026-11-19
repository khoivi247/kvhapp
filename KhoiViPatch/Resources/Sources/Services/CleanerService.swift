import Foundation

final class CleanerService {
    static let shared = CleanerService()
    private let fm = FileManager.default

    func scanCleanableTargets(from containers: [AppContainerInfo]) -> [CleanableTarget] {
        var results: [CleanableTarget] = []

        for container in containers {
            let subTargets = [
                ("Caches", container.rootURL.appendingPathComponent("Library/Caches")),
                ("Temporary (tmp)", container.rootURL.appendingPathComponent("tmp"))
            ]

            for (label, folderURL) in subTargets where fm.fileExists(atPath: folderURL.path) {
                let stats = directoryStats(at: folderURL)
                results.append(CleanableTarget(
                    title: "\(container.name) — \(label)",
                    bundleId: container.bundleId,
                    pathURL: folderURL,
                    reclaimableBytes: stats.bytes,
                    fileCount: stats.count,
                    isSelected: true
                ))
            }
        }

        return results
    }

    @discardableResult
    func clean(targets: [CleanableTarget]) -> (freedBytes: Int64, removedFiles: Int) {
        var totalFreed: Int64 = 0
        var totalRemoved = 0

        for target in targets where target.isSelected {
            guard let items = try? fm.contentsOfDirectory(at: target.pathURL, includingPropertiesForKeys: nil) else {
                continue
            }
            for item in items {
                let stats = directoryStats(at: item)
                do {
                    try fm.removeItem(at: item)
                    totalFreed += stats.bytes
                    totalRemoved += max(stats.count, 1)
                } catch {
                    // Ignore locked system files
                }
            }
        }
        return (totalFreed, totalRemoved)
    }

    private func directoryStats(at url: URL) -> (bytes: Int64, count: Int) {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return (0, 0) }
        if !isDir.boolValue {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return (Int64(size), 1)
        }

        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return (0, 0)
        }

        var total: Int64 = 0
        var count = 0
        for case let fileURL as URL in enumerator {
            if let vals = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
               vals.isRegularFile == true {
                total += Int64(vals.fileSize ?? 0)
                count += 1
            }
        }
        return (total, count)
    }
}
