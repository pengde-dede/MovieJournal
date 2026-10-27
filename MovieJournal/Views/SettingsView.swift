import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            Section("数据来源") {
                LabeledContent("TMDB Key", value: "尚未配置")
                LabeledContent("OMDb Key（可选）", value: "尚未配置")
                Text("API Key 设置尚未启用。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("本地存储") {
                Text("观影记录保存在本机。")
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 460, height: 300)
        .navigationTitle("设置")
    }
}
