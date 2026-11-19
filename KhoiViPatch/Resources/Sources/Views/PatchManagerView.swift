import SwiftUI
import UniformTypeIdentifiers

struct PatchManagerView: View {
    @Binding var newlyImportedURL: URL?
    @EnvironmentObject var accessManager: ContainerAccessManager

    @State private var savedPatches: [LoadedKVHPackage] = []
    @State private var backups: [KVHBackupRecord] = []
    @State private var showFileImporter = false
    @State private var showCreatePatchSheet = false
    @State private var selectedPatchForApply: LoadedKVHPackage?
    @State private var passwordInput = ""
    @State private var showPasswordPrompt = false
    @State private var statusMessage: String?
    @State private var isErrorStatus = false

    private let kvhType = UTType(filenameExtension: "kvh") ?? .data

    var body: some View {
        NavigationView {
            List {
                if let msg = statusMessage {
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: isErrorStatus ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                                .foregroundColor(isErrorStatus ? .red : .green)
                            Text(msg)
                                .font(.caption)
                        }
                    }
                }

                Section {
                    Button {
                        showFileImporter = true
                    } label: {
                        Label("Nhập tệp .kvh từ Tệp (Files)", systemImage: "square.and.arrow.down.fill")
                            .foregroundColor(Color(red: 0.0, green: 0.9, blue: 0.78))
                    }

                    Button {
                        showCreatePatchSheet = true
                    } label: {
                        Label("Tạo gói .kvh mới", systemImage: "plus.square.on.square")
                            .foregroundColor(.mint)
                    }
                }

                Section(header: Text("Danh sách Patch (.kvh) — \(savedPatches.count)")) {
                    if savedPatches.isEmpty {
                        Text("Chưa có gói .kvh nào. Hãy nhập file .kvh hoặc tạo từ trình duyệt tệp.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(savedPatches) { pkg in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(pkg.manifest.name)
                                        .font(.headline)
                                    Spacer()
                                    if pkg.isPasswordProtected {
                                        Image(systemName: "lock.fill")
                                            .foregroundColor(.orange)
                                            .font(.caption)
                                    }
                                    Text("v\(pkg.manifest.version)")
                                        .font(.caption2.monospaced())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.cyan.opacity(0.2))
                                        .cornerRadius(4)
                                }

                                Text("Target: \(pkg.manifest.targetBundleId)")
                                    .font(.caption.monospaced())
                                    .foregroundColor(Color(red: 0.0, green: 0.9, blue: 0.78))

                                Text(pkg.manifest.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                HStack {
                                    Text("Tác giả: \(pkg.manifest.author) • \(pkg.manifest.operations.count) tác vụ")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                    Spacer()
                                    Button("Áp dụng") {
                                        triggerApply(pkg)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(Color(red: 0.0, green: 0.75, blue: 0.65))
                                    .controlSize(.small)
                                }
                                .padding(.top, 2)
                            }
                            .padding(.vertical, 4)
                            .swipeActions {
                                Button(role: .destructive) {
                                    try? FileManager.default.removeItem(at: pkg.fileURL)
                                    reloadAll()
                                } label: {
                                    Label("Xóa", systemImage: "trash")
                                }
                            }
                        }
                    }
                }

                Section(header: Text("Sao lưu & Khôi phục (\(backups.count))")) {
                    if backups.isEmpty {
                        Text("Bản sao lưu tự động sẽ được tạo trước mỗi lần chạy .kvh.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(backups) { rec in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(rec.patchName)
                                        .font(.subheadline.weight(.medium))
                                    Text("\(rec.targetBundleId) • \(rec.backedUpFiles.count) tệp")
                                        .font(.caption2.monospaced())
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Button("Khôi phục") {
                                    restoreBackup(rec)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Trình quản lý .kvh")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { reloadAll() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .onAppear { reloadAll() }
            .onChange(of: newlyImportedURL) { _ in
                reloadAll()
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [kvhType, .zip, .data],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
            .alert("Nhập mật khẩu gói .kvh", isPresented: $showPasswordPrompt) {
                SecureField("Mật khẩu mở khóa", text: $passwordInput)
                Button("Xác nhận") {
                    if let pkg = selectedPatchForApply {
                        executeApply(pkg, password: passwordInput)
                    }
                }
                Button("Hủy", role: .cancel) {}
            } message: {
                Text("Gói patch này được bảo vệ bằng mã băm SHA-256.")
            }
            .sheet(isPresented: $showCreatePatchSheet) {
                CreateKVHPatchSheet(onCreated: {
                    reloadAll()
                })
            }
        }
    }

    private func reloadAll() {
        savedPatches = KVHArchiveEngine.shared.listSavedPatches()
        backups = KVHArchiveEngine.shared.listBackups()
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let pkg = try KVHArchiveEngine.shared.importKVHFile(from: url)
                statusMessage = "Đã nhập thành công: \(pkg.manifest.name) (\(pkg.fileName))"
                isErrorStatus = false
                reloadAll()
            } catch {
                statusMessage = error.localizedDescription
                isErrorStatus = true
            }
        case .failure(let error):
            statusMessage = error.localizedDescription
            isErrorStatus = true
        }
    }

    private func triggerApply(_ pkg: LoadedKVHPackage) {
        if pkg.isPasswordProtected {
            selectedPatchForApply = pkg
            passwordInput = ""
            showPasswordPrompt = true
        } else {
            executeApply(pkg, password: nil)
        }
    }

    private func executeApply(_ pkg: LoadedKVHPackage, password: String?) {
        guard let targetRoot = accessManager.resolveTargetContainerURL(for: pkg.manifest.targetBundleId) else {
            statusMessage = KVHError.targetContainerNotAccessible(pkg.manifest.targetBundleId).localizedDescription
            isErrorStatus = true
            return
        }

        do {
            let record = try KVHArchiveEngine.shared.applyPackage(pkg, password: password, targetRootURL: targetRoot)
            statusMessage = "Đã áp dụng '\(pkg.manifest.name)' thành công! Mã sao lưu: \(record.id)"
            isErrorStatus = false
            reloadAll()
        } catch {
            statusMessage = error.localizedDescription
            isErrorStatus = true
        }
    }

    private func restoreBackup(_ record: KVHBackupRecord) {
        guard let targetRoot = accessManager.resolveTargetContainerURL(for: record.targetBundleId) else {
            statusMessage = "Không tìm thấy container \(record.targetBundleId) để khôi phục."
            isErrorStatus = true
            return
        }
        do {
            try KVHArchiveEngine.shared.restoreBackup(record, to: targetRoot)
            statusMessage = "Đã khôi phục sao lưu \(record.id) cho \(record.targetBundleId)."
            isErrorStatus = false
        } catch {
            statusMessage = error.localizedDescription
            isErrorStatus = true
        }
    }
}

struct CreateKVHPatchSheet: View {
    let onCreated: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = "Custom_KVH_Patch"
    @State private var targetBundleId = "com.khoividev.sandbox.demo"
    @State private var description = "Bản vá tùy chỉnh định dạng .kvh"
    @State private var relativeTargetPath = "Documents/config.json"
    @State private var payloadContent = "{\n  \"author\": \"KhoiViDev\",\n  \"boost\": true\n}"
    @State private var password = ""
    @State private var errorMsg: String?

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Thông tin gói .kvh")) {
                    TextField("Tên Patch", text: $name)
                    TextField("Target Bundle ID", text: $targetBundleId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Mô tả", text: $description)
                    SecureField("Mật khẩu (bỏ trống nếu không khóa)", text: $password)
                }

                Section(header: Text("Tệp đích & Nội dung")) {
                    TextField("Đường dẫn tương đối (vd: Documents/config.json)", text: $relativeTargetPath)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextEditor(text: $payloadContent)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 160)
                }

                if let err = errorMsg {
                    Text(err).foregroundColor(.red).font(.caption)
                }
            }
            .navigationTitle("Tạo gói .kvh")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Hủy") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Đóng gói") {
                        createNow()
                    }
                    .font(.body.weight(.semibold))
                }
            }
        }
    }

    private func createNow() {
        guard let data = payloadContent.data(using: .utf8) else { return }
        do {
            _ = try KVHArchiveEngine.shared.createPackage(
                name: name,
                targetBundleId: targetBundleId,
                description: description,
                password: password.isEmpty ? nil : password,
                sourceFiles: [(relativeTargetPath: relativeTargetPath, data: data)]
            )
            onCreated()
            dismiss()
        } catch {
            errorMsg = error.localizedDescription
        }
    }
}
