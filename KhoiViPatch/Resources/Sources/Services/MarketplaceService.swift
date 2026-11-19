import Foundation

final class MarketplaceService: ObservableObject {
    static let shared = MarketplaceService()

    @Published var repoURLs: [String] = []
    @Published var loadedRepos: [KVHRepoManifest] = []
    @Published var isLoading = false
    @Published var lastError: String?

    private let savedReposKey = "kvh_saved_repo_urls"

    private init() {
        repoURLs = UserDefaults.standard.stringArray(forKey: savedReposKey) ?? []
    }

    func addRepoURL(_ rawURL: String) {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, URL(string: trimmed) != nil else { return }
        if !repoURLs.contains(trimmed) {
            repoURLs.append(trimmed)
            UserDefaults.standard.set(repoURLs, forKey: savedReposKey)
        }
    }

    func removeRepoURL(at indexSet: IndexSet) {
        repoURLs.remove(atOffsets: indexSet)
        UserDefaults.standard.set(repoURLs, forKey: savedReposKey)
    }

    @MainActor
    func refreshAllRepos() async {
        isLoading = true
        lastError = nil
        var manifests: [KVHRepoManifest] = []

        for urlString in repoURLs {
            guard let url = URL(string: urlString) else { continue }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let manifest = try JSONDecoder().decode(KVHRepoManifest.self, from: data)
                manifests.append(manifest)
            } catch {
                lastError = "Lỗi tải repo \(url.host ?? urlString): \(error.localizedDescription)"
            }
        }

        loadedRepos = manifests
        isLoading = false
    }

    @MainActor
    func downloadAndImport(package: KVHRepoPackage) async throws -> LoadedKVHPackage {
        guard let url = URL(string: package.downloadURL) else {
            throw KVHError.operationFailed("URL tải xuống không hợp lệ.")
        }

        let (data, _) = try await URLSession.shared.data(from: url)

        if let expectedHash = package.sha256, !expectedHash.isEmpty {
            let actualHash = KVHArchiveEngine.shared.sha256Hex(data)
            if actualHash.lowercased() != expectedHash.lowercased() {
                throw KVHError.operationFailed("SHA-256 không khớp! Gói tải về có thể bị hỏng.")
            }
        }

        let fileName = package.name.replacingOccurrences(of: " ", with: "_") + ".kvh"
        let destURL = KVHArchiveEngine.shared.patchesDirectory.appendingPathComponent(fileName)
        try data.write(to: destURL, options: .atomic)
        return try KVHArchiveEngine.shared.loadPackage(from: destURL)
    }
}
