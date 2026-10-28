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
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button("重新检查保存状态") { Task { await settings.refresh() } }
                        .disabled(settings.isWorking)
                    if settings.isWorking { ProgressView().controlSize(.small) }
                }
            }
            Section("关于观影记录与数据来源") {
                HStack {
                    Text("观影记录").font(.headline)
                    Spacer()
                    Image("TMDBLogo").resizable().scaledToFit().frame(width: 90, height: 28)
                }
                Text("影片资料与海报来自 TMDB；IMDb、烂番茄评分由 OMDb 提供。")
                    .font(.callout).foregroundStyle(.secondary)
                Text("This product uses the TMDB API but is not endorsed or certified by TMDB.")
                    .font(.caption).foregroundStyle(.secondary)
                if let url = URL(string: "https://www.themoviedb.org") {
                    Link("访问 TMDB", destination: url)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 600, height: 720)
        .navigationTitle("设置")
        .task { await settings.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await settings.refresh() } }
        }
    }
}

private struct APIKeySection: View {
    let provider: APIKeyProvider
    let settings: SettingsViewModel

    var body: some View {
        Section(provider.title) {
            Text(provider.explanation).font(.callout).foregroundStyle(.secondary)
            KeyStatusView(status: settings.status(for: provider))
            SecureField("输入新的 \(provider.shortName) Key", text: Binding(
                get: { settings.input(for: provider) },
                set: { settings.setInput($0, for: provider) }
            ))
            .disabled(settings.isWorking)
            .onSubmit { Task { await settings.save(provider) } }
            HStack {
                Button("保存") { Task { await settings.save(provider) } }
                    .buttonStyle(.borderedProminent)
                    .disabled(!settings.canSave(provider))
                    .accessibilityLabel("保存 \(provider.shortName) Key")
                Button("验证") { settings.validate(provider) }
                    .disabled(!settings.canValidate(provider))
                    .help("验证已保存的 Key；输入新内容后请先保存。")
                    .accessibilityLabel("验证 \(provider.shortName) Key")
                Button("清除", role: .destructive) { Task { await settings.delete(provider) } }
                    .disabled(!settings.canDelete(provider))
                    .accessibilityLabel("清除 \(provider.shortName) Key")
                Spacer()
                if let url = provider.helpURL { Link("获取 Key", destination: url) }
            }
            if let warning = settings.warnings[provider] {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            if let notice = settings.notices[provider] {
                Label(notice.message, systemImage: notice.isFailure ? "exclamationmark.triangle" : "checkmark.circle")
                    .font(.callout)
                    .foregroundStyle(notice.isFailure ? Color.red : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if settings.validatingProviders.contains(provider) {
                ProgressView("正在验证…").controlSize(.small)
            } else if let result = settings.validationResults[provider] {
                validationResult(result)
            } else {
                Text("尚未验证。验证使用已保存的 Key，结果只保留在本次运行中。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func validationResult(_ result: KeyValidationResult) -> some View {
        switch result {
        case .valid:
            Label("有效", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .invalid:
            Label("无效，请检查保存的 Key。", systemImage: "xmark.circle.fill").foregroundStyle(.red)
        case .networkFailure(let message):
            Label("网络失败：\(message)", systemImage: "wifi.exclamationmark").foregroundStyle(.orange)
        case .unavailable(let message):
            Label("暂时无法验证：\(message)", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
        }
    }
}

private struct KeyStatusView: View {
    let status: SettingsViewModel.KeyStatus
    var body: some View {
        switch status {
        case .checking: Label("正在检查保存状态…", systemImage: "hourglass").foregroundStyle(.secondary)
        case .missing: Label("未配置", systemImage: "key").foregroundStyle(.secondary)
        case .saved: Label("已保存", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .unavailable(let message):
            Label("无法检查保存状态：\(message)", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
        }
    }
}
