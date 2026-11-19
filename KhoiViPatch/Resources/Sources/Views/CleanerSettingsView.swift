import SwiftUI

struct CleanerSettingsView: View {
    @EnvironmentObject var accessManager: ContainerAccessManager
    @State private var targets: [CleanableTarget] = []
    @State private var cleanReport: String?

    var totalSelectedBytes: Int64 {
        targets.filter(\.isSelected).reduce(0) { $0 + $1.reclaimableBytes }
    }

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Dọn dẹp Cache & Tạm (Cleaner)")) {
                    if targets.isEmpty {
                        Text("Nhấn 'Quét dữ liệu tạm' để kiểm tra Library/Caches và tmp.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach($targets) { $target in
                            Toggle(isOn: $target.isSelected) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(target.title)
                                        .font(.subheadline)
                                    Text("\(target.fileCount) tệp • \(ByteCountFormatter.string(fromByteCount: target.reclaimableBytes, countStyle: .file))")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }

                    HStack {
                        Button("Quét lại") {
                            scanNow()
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        Button("Dọn \(ByteCountFormatter.string(fromByteCount: totalSelectedBytes, countStyle: .file))") {
                            let res = CleanerService.shared.clean(targets: targets)
                            cleanReport = "Đã giải phóng \(ByteCountFormatter.string(fromByteCount: res.freedBytes, countStyle: .file)) (\(res.removedFiles) mục)."
                            scanNow()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .disabled(targets.isEmpty)
                    }

                    if let report = cleanReport {
                        Text(report)
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }

                Section(header: Text("Chế độ truy cập Container")) {
                    Picker("Access Provider", selection: $accessManager.accessMode) {
                        ForEach(ContainerAccessMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .onChange(of: accessManager.accessMode) { _ in
                        accessManager.reloadContainers()
                    }
                }

                Section(header: Text("Chẩn đoán Hệ thống & Entitlement")) {
                    DiagnosticRow(label: "Tác giả", value: "KhoiViDev")
                    DiagnosticRow(label: "Định dạng Patch", value: ".kvh")
                    DiagnosticRow(label: "Phiên bản iOS", value: accessManager.currentIOSVersion)
                    DiagnosticRow(label: "Bundle ID hiện tại", value: accessManager.currentBundleIdentifier)
                    DiagnosticRow(label: "Khớp MobileHouseArrest", value: accessManager.isMobileHouseArrestBundleId ? "Có" : "Không")
                    DiagnosticRow(label: "Đọc System Containers", value: accessManager.hasSystemContainerAccess ? "Khả dụng" : "Bị chặn bởi Sandbox")
                }

                Section(footer: Text("KhoiViPatch Engine • Author: KhoiViDev. Trên các bản iOS mới đã vá sandbox (như iOS 26.5.2), truy cập chéo container của ứng dụng khác yêu cầu module exploit tương thích + chứng chỉ Enterprise hỗ trợ Bundle ID hệ thống.")) {
                    EmptyView()
                }
            }
            .navigationTitle("Dọn dẹp & Hệ thống")
            .onAppear { scanNow() }
        }
    }

    private func scanNow() {
        targets = CleanerService.shared.scanCleanableTargets(from: accessManager.containers)
    }
}

private struct DiagnosticRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
                .font(.caption.monospaced())
        }
    }
}
