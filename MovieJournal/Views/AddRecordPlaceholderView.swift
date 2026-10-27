import SwiftUI

struct AddRecordPlaceholderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsViewModel.self) private var settings

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.tint)
            Text("添加观影记录")
                .font(.title2.bold())

            switch settings.status(for: .tmdb) {
            case .checking:
                ProgressView("正在检查 TMDB Key…")
            case .missing:
                Text("请先在设置中填写 TMDB Key。")
                SettingsLink {
                    Text("打开设置")
                }
                .buttonStyle(.borderedProminent)
            case .saved:
                Label("TMDB Key 已保存，尚未联网验证。", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
                Text("片名搜索尚未启用。")
                    .foregroundStyle(.secondary)
            case .unavailable(let message):
                Text("暂时无法检查 TMDB Key")
                    .font(.headline)
                Text(message)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("重试") {
                        Task { await settings.refresh() }
                    }
                    .disabled(settings.isWorking)
                    SettingsLink {
                        Text("打开设置")
                    }
                }
            }

            Button("关闭") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .multilineTextAlignment(.center)
        .padding(40)
        .frame(width: 440)
        .task { await settings.refreshIfNeeded() }
    }
}
