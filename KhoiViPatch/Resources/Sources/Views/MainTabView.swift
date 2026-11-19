import SwiftUI

struct MainTabView: View {
    @Binding var selectedTab: Int
    @Binding var importedPatchURL: URL?

    var body: some View {
        TabView(selection: $selectedTab) {
            AppBrowserView()
                .tabItem {
                    Label("Ứng dụng", systemImage: "folder.badge.gearshape")
                }
                .tag(0)

            PatchManagerView(newlyImportedURL: $importedPatchURL)
                .tabItem {
                    Label("Patch .kvh", systemImage: "shippingbox.fill")
                }
                .tag(1)

            MarketplaceView(onDownloadedPatch: {
                selectedTab = 1
            })
                .tabItem {
                    Label("Kho Repo", systemImage: "tray.and.arrow.down.fill")
                }
                .tag(2)

            CleanerSettingsView()
                .tabItem {
                    Label("Dọn dẹp", systemImage: "sparkles")
                }
                .tag(3)
        }
        .accentColor(Color(red: 0.0, green: 0.9, blue: 0.78))
    }
}
