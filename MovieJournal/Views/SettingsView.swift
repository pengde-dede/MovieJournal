import SwiftUI

struct SettingsView: View {
    @Environment(SettingsViewModel.self) private var settings
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Form {
            ForEach(APIKeyProvider.allCases) { provider in
                APIKeySection(provider: provider, settings: settings)
            }
            Section("本机存储") {
                Text("Key 保存在这台 Mac 的钥匙串中，保存后不回显。输入新的 Key 并保存即可更换。")
                Text("留空不会删除已保存的 Key；需要删除时请点击对应的“清除”按钮。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("重新检查保存状态") {
                        Task { await settings.refresh() }
                    }
                    .disabled(settings.isWorking)
                    if settings.isWorking {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 570, height: 620)
        .navigationTitle("设置")
        .task { await settings.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await settings.refresh() }
            }
        }
    }
}

private struct APIKeySection: View {
    let provider: APIKeyProvider
    let settings: SettingsViewModel

    var body: some View {
        Section(provider.title) {
            Text(provider.explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
            KeyStatusView(status: settings.status(for: provider))
            SecureField("输入新的 \(provider.shortName) Key", text: Binding(
                get: { settings.input(for: provider) },
                set: { settings.setInput($0, for: provider) }
            ))
            .disabled(settings.isWorking)
            .onSubmit {
                Task { await settings.save(provider) }
            }
            HStack {
                Button("保存") {
                    Task { await settings.save(provider) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!settings.canSave(provider))
                .accessibilityLabel("保存 \(provider.shortName) Key")

                Button("清除", role: .destructive) {
                    Task { await settings.delete(provider) }
                }
                .disabled(!settings.canDelete(provider))
                .accessibilityLabel("清除 \(provider.shortName) Key")

                Spacer()
                if let url = provider.helpURL {
                    Link("获取 \(provider.shortName) Key", destination: url)
                }
            }
            if let notice = settings.notices[provider] {
                Label(notice.message, systemImage: notice.isFailure ? "exclamationmark.triangle" : "checkmark.circle")
                    .font(.callout)
                    .foregroundStyle(notice.isFailure ? Color.red : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("\(provider.rawValue)-notice")
            }
        }
    }
}

private struct KeyStatusView: View {
    let status: SettingsViewModel.KeyStatus

    var body: some View {
        switch status {
        case .checking:
            Label("正在检查保存状态…", systemImage: "hourglass")
                .foregroundStyle(.secondary)
        case .missing:
            Label("未配置", systemImage: "key")
                .foregroundStyle(.secondary)
        case .saved:
            Label("已保存（尚未联网验证）", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .unavailable(let message):
            Label("无法检查保存状态：\(message)", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
