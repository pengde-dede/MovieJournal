import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct BackupView: View {
    let context: ModelContext
    let posters: any PosterFileManaging
    let cleanup: PosterCleanupCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var preview: LibraryBackup?
    @State private var message = ""
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("备份与恢复").font(.title2.bold())
            Text("导出作品、观看状态、评分、观影历史和已缓存的海报。恢复时保留本机已有作品，跳过重复项。")
            HStack {
                Button("导出备份…") { exportBackup() }
                Button("选择备份…") { selectBackup() }
            }
            if !message.isEmpty { Text(message).textSelection(.enabled) }
            HStack {
                if busy { ProgressView().controlSize(.small) }
                Spacer()
                Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction)
                if let preview {
                    Button("确认恢复") {
                        run {
                            let count = try await preview.restore(context: context, cache: posters)
                            self.preview = nil
                            message = "已恢复 \(count) 部作品。"
                        }
                    }.buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(24).frame(width: 480).disabled(busy)
        .interactiveDismissDisabled(busy)
    }

    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        guard let session = cleanup.beginAdding() else { message = "正在维护海报，请稍后重试。"; return }
        busy = true
        Task {
            defer {
                busy = false
                cleanup.finishAdding(session, store: RecordStore(context: context))
            }
            do { try await operation() }
            catch { message = error.localizedDescription }
        }
    }

    private func exportBackup() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "观影记录备份.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        preview = nil
        run {
            let backup = try await LibraryBackup.snapshot(context: context, cache: posters)
            try await Task.detached {
                try JSONEncoder().encode(backup).write(to: url, options: .atomic)
            }.value
            message = "已导出 \(backup.entries.count) 部作品和 \(backup.posters.count) 张海报。"
        }
    }

    private func selectBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        preview = nil
        run {
            let backup = try await Task.detached {
                try JSONDecoder().decode(LibraryBackup.self, from: Data(contentsOf: url))
            }.value
            let count = try backup.additions(to: context).count
            message = "共 \(backup.entries.count) 部，将添加 \(count) 部，跳过 \(backup.entries.count - count) 部。"
            preview = count > 0 ? backup : nil
        }
    }
}
