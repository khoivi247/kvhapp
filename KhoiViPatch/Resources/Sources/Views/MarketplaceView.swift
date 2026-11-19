import SwiftUI

struct MarketplaceView: View {
    @EnvironmentObject var marketplace: MarketplaceService
    let onDownloadedPatch: () -> Void

    @State private var showAddRepoAlert = false
    @State private var newRepoURL = ""
    @State private var downloadStatus: String?

    var body: some View {
        NavigationView {
            List {
                if let msg = downloadStatus ?? marketplace.lastError {
                    Section {
                        Text(msg)
                            .font(.caption)
                            .foregroundColor(.cyan)
                    }
                }

                Section(header: Text("Nguồn Repo (.json)")) {
                    if marketplace.repoURLs.isEmpty {
                        Text("Chưa thêm nguồn repo nào. Bấm '+' để thêm link repo.json chứa các gói .kvh.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(marketplace.repoURLs, id: \.self) { url in
                            Text(url)
                                .font(.caption.monospaced())
                                .lineLimit(1)
                        }
                        .onDelete(perform: marketplace.removeRepoURL)
                    }
                }

                ForEach(marketplace.loadedRepos, id: \.repoName) { repo in
                    Section(header: Text("\(repo.repoName) — \(repo.repoAuthor)")) {
                        ForEach(repo.packages) { pkg in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(pkg.name)
                                        .font(.headline)
                                    Spacer()
                                    Text("v\(pkg.version)")
                                        .font(.caption2.monospaced())
                                        .foregroundColor(.cyan)
                                }
                                Text(pkg.targetBundleId)
                                    .font(.caption2.monospaced())
                                    .foregroundColor(.secondary)
                                Text(pkg.summary)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                HStack {
                                    Text(pkg.category)
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.mint.opacity(0.15))
                                        .cornerRadius(4)
                                    Spacer()
                                    Button("Tải .kvh") {
                                        Task {
                                            do {
                                                let loaded = try await marketplace.downloadAndImport(package: pkg)
                                                downloadStatus = "Đã tải \(loaded.fileName)"
                                                onDownloadedPatch()
                                            } catch {
                                                downloadStatus = error.localizedDescription
                                            }
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
            }
            .navigationTitle("Kho Repo .kvh")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        Task { await marketplace.refreshAllRepos() }
                    } label: {
                        if marketplace.isLoading {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        newRepoURL = ""
                        showAddRepoAlert = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert("Thêm nguồn Repo (.json)", isPresented: $showAddRepoAlert) {
                TextField("https://example.com/repo.json", text: $newRepoURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Thêm") {
                    marketplace.addRepoURL(newRepoURL)
                    Task { await marketplace.refreshAllRepos() }
                }
                Button("Hủy", role: .cancel) {}
            }
        }
    }
}
