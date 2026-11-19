import SwiftUI

struct AppBrowserView: View {
    @EnvironmentObject var accessManager: ContainerAccessManager
    @State private var searchText = ""
    @State private var showNewWorkspaceAlert = false
    @State private var newBundleIdInput = ""
    @State private var alertMessage: String?

    var filteredContainers: [AppContainerInfo] {
        let sorted = accessManager.containers.sorted {
            if $0.isFavorite != $1.isFavorite { return $0.isFavorite && !$1.isFavorite }
            return $0.name < $1.name
        }
        if searchText.isEmpty { return sorted }
        return sorted.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.bundleId.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("KVH App-Data Browser")
                                .font(.headline)
                                .foregroundColor(.white)
                            Text("KhoiViDev • \(accessManager.accessMode.rawValue)")
                                .font(.caption)
                                .foregroundColor(Color(red: 0.0, green: 0.9, blue: 0.78))
                        }
                        Spacer()
                        Image(systemName: accessManager.hasSystemContainerAccess ? "lock.open.fill" : "shield.lefthalf.filled")
                            .foregroundColor(accessManager.hasSystemContainerAccess ? .green : .orange)
                            .font(.title3)
                    }
                    .padding(.vertical, 4)
                }

                Section(header: Text("Containers & Workspaces (\(filteredContainers.count))")) {
                    ForEach(filteredContainers) { container in
                        NavigationLink(destination: DirectoryExplorerView(
                            containerRoot: container.rootURL,
                            currentURL: container.rootURL,
                            containerBundleId: container.bundleId,
                            title: container.name
                        )) {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color(red: 0.08, green: 0.16, blue: 0.22))
                                        .frame(width: 42, height: 42)
                                    Image(systemName: container.isSystemOrPrivileged ? "app.badge.checkmark" : "folder.fill")
                                        .foregroundColor(Color(red: 0.0, green: 0.9, blue: 0.78))
                                }

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(container.name)
                                            .font(.subheadline.weight(.semibold))
                                        if container.isFavorite {
                                            Image(systemName: "star.fill")
                                                .font(.caption2)
                                                .foregroundColor(.yellow)
                                        }
                                    }
                                    Text(container.bundleId)
                                        .font(.caption.monospaced())
                                        .foregroundColor(.secondary)
                                    Text(container.descriptionNote)
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                        .lineLimit(1)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $searchText, prompt: "Tìm theo tên hoặc Bundle ID...")
            .navigationTitle("Ứng dụng")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        newBundleIdInput = ""
                        showNewWorkspaceAlert = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        accessManager.reloadContainers()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .alert("Tạo Workspace theo Bundle ID", isPresented: $showNewWorkspaceAlert) {
                TextField("vd: com.example.game", text: $newBundleIdInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Tạo") {
                    guard !newBundleIdInput.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    do {
                        _ = try accessManager.createWorkspace(bundleId: newBundleIdInput)
                    } catch {
                        alertMessage = error.localizedDescription
                    }
                }
                Button("Hủy", role: .cancel) {}
            } message: {
                Text("Tạo cây thư mục chuẩn (Documents, Library/Preferences) để chỉnh sửa file và đóng gói thành tệp .kvh.")
            }
            .alert("Thông báo", isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage ?? "")
            }
        }
    }
}

struct DirectoryExplorerView: View {
    let containerRoot: URL
    let currentURL: URL
    let containerBundleId: String
    let title: String

    @State private var items: [ContainerFileItem] = []
    @State private var selectedFileForEdit: ContainerFileItem?
    @State private var showNewFileAlert = false
    @State private var newFileName = ""
    @State private var statusBanner: String?

    var body: some View {
        List {
            if let banner = statusBanner {
                Section {
                    Text(banner)
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }

            if items.isEmpty {
                Text("Thư mục trống")
                    .foregroundColor(.secondary)
            } else {
                ForEach(items) { item in
                    if item.isDirectory {
                        NavigationLink(destination: DirectoryExplorerView(
                            containerRoot: containerRoot,
                            currentURL: item.url,
                            containerBundleId: containerBundleId,
                            title: item.name
                        )) {
                            FileRowView(item: item)
                        }
                    } else {
                        Button {
                            selectedFileForEdit = item
                        } label: {
                            FileRowView(item: item)
                        }
                        .contextMenu {
                            Button {
                                selectedFileForEdit = item
                            } label: {
                                Label("Mở & Sửa tệp", systemImage: "pencil")
                            }

                            Button {
                                exportSingleFileAsKVH(item)
                            } label: {
                                Label("Đóng gói thành .kvh", systemImage: "shippingbox.fill")
                            }

                            Button(role: .destructive) {
                                try? FileManager.default.removeItem(at: item.url)
                                reload()
                            } label: {
                                Label("Xóa tệp", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    newFileName = "patch_config.json"
                    showNewFileAlert = true
                } label: {
                    Image(systemName: "doc.badge.plus")
                }
            }
        }
        .onAppear { reload() }
        .sheet(item: $selectedFileForEdit) { fileItem in
            FileEditorSheet(fileItem: fileItem, bundleId: containerBundleId, containerRoot: containerRoot) {
                reload()
            }
        }
        .alert("Tạo tệp mới", isPresented: $showNewFileAlert) {
            TextField("Tên tệp (vd: config.plist hoặc tweak.json)", text: $newFileName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Tạo") {
                createEmptyFile(named: newFileName)
            }
            Button("Hủy", role: .cancel) {}
        }
    }

    private func reload() {
        items = ContainerAccessManager.shared.listDirectory(at: currentURL)
    }

    private func createEmptyFile(named name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let dest = currentURL.appendingPathComponent(clean)
        let defaultContent: String
        if clean.hasSuffix(".plist") {
            defaultContent = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Author</key>
                <string>KhoiViDev</string>
            </dict>
            </plist>
            """
        } else {
            defaultContent = "{\n  \"author\": \"KhoiViDev\"\n}\n"
        }
        try? defaultContent.data(using: .utf8)?.write(to: dest)
        reload()
    }

    private func exportSingleFileAsKVH(_ item: ContainerFileItem) {
        guard let data = try? Data(contentsOf: item.url) else { return }
        let rel = item.url.path.replacingOccurrences(of: containerRoot.path + "/", with: "")
        do {
            let kvhURL = try KVHArchiveEngine.shared.createPackage(
                name: "\(item.name)_Patch",
                targetBundleId: containerBundleId,
                description: "Tạo từ \(rel) bởi KhoiViDev",
                password: nil,
                sourceFiles: [(relativeTargetPath: rel, data: data)]
            )
            statusBanner = "Đã tạo: \(kvhURL.lastPathComponent) trong tab Patch .kvh"
        } catch {
            statusBanner = "Lỗi: \(error.localizedDescription)"
        }
    }
}

struct FileRowView: View {
    let item: ContainerFileItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .foregroundColor(iconColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                if !item.isDirectory {
                    Text(ByteCountFormatter.string(fromByteCount: item.sizeBytes, countStyle: .file))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var iconName: String {
        if item.isDirectory { return "folder.fill" }
        if item.fileExtension == "plist" { return "list.bullet.rectangle.portrait" }
        if item.fileExtension == "json" { return "curlybraces" }
        if item.fileExtension == "kvh" { return "shippingbox.fill" }
        return "doc.text"
    }

    private var iconColor: Color {
        if item.isDirectory { return .cyan }
        if item.isPlistOrJSON { return .mint }
        if item.fileExtension == "kvh" { return .orange }
        return .gray
    }
}

struct FileEditorSheet: View {
    let fileItem: ContainerFileItem
    let bundleId: String
    let containerRoot: URL
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var contentText = ""
    @State private var errorMessage: String?
    @State private var infoMessage: String?

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if let err = errorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(Color.red.opacity(0.15))
                }
                if let info = infoMessage {
                    Text(info)
                        .font(.caption)
                        .foregroundColor(.green)
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(Color.green.opacity(0.15))
                }

                TextEditor(text: $contentText)
                    .font(.system(.caption, design: .monospaced))
                    .padding(8)
            }
            .navigationTitle(fileItem.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Đóng") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Button("Xuất .kvh") {
                            exportCurrentToKVH()
                        }
                        Button("Lưu") {
                            saveChanges()
                        }
                        .font(.body.weight(.semibold))
                    }
                }
            }
            .onAppear {
                do {
                    contentText = try PlistJsonEditorService.readAsPrettyText(url: fileItem.url)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func saveChanges() {
        do {
            try PlistJsonEditorService.saveEditedText(contentText, to: fileItem.url)
            errorMessage = nil
            infoMessage = "Đã lưu & kiểm tra cú pháp thành công!"
            onSaved()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func exportCurrentToKVH() {
        saveChanges()
        guard errorMessage == nil, let data = try? Data(contentsOf: fileItem.url) else { return }
        let rel = fileItem.url.path.replacingOccurrences(of: containerRoot.path + "/", with: "")
        do {
            let out = try KVHArchiveEngine.shared.createPackage(
                name: "\(fileItem.name)_KVH",
                targetBundleId: bundleId,
                description: "Gói .kvh xuất từ trình chỉnh sửa KhoiViPatch",
                password: nil,
                sourceFiles: [(relativeTargetPath: rel, data: data)]
            )
            infoMessage = "Đã đóng gói \(out.lastPathComponent)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
