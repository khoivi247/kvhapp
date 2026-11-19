import SwiftUI

@main
struct KhoiViPatchApp: App {
    @StateObject private var accessManager = ContainerAccessManager.shared
    @StateObject private var marketplace = MarketplaceService.shared
    @State private var selectedTab: Int = 0
    @State private var importedPatchURL: URL?
    @State private var importAlertMessage: String?

    var body: some Scene {
        WindowGroup {
            MainTabView(
                selectedTab: $selectedTab,
                importedPatchURL: $importedPatchURL
            )
            .environmentObject(accessManager)
            .environmentObject(marketplace)
            .preferredColorScheme(.dark)
            .onOpenURL { url in
                guard url.pathExtension.lowercased() == "kvh" else { return }
                do {
                    let pkg = try KVHArchiveEngine.shared.importKVHFile(from: url)
                    importedPatchURL = pkg.fileURL
                    selectedTab = 1
                } catch {
                    importAlertMessage = error.localizedDescription
                }
            }
            .alert("Nhập gói .kvh", isPresented: Binding(
                get: { importAlertMessage != nil },
                set: { if !$0 { importAlertMessage = nil } }
            )) {
                Button("Đóng", role: .cancel) {}
            } message: {
                Text(importAlertMessage ?? "")
            }
        }
    }
}
