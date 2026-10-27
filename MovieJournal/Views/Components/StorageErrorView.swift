import SwiftUI

struct StorageErrorView: View {
    let errorDescription: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("无法打开本地资料库", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            VStack(spacing: 12) {
                Text("请检查磁盘空间和文件权限后重试。原有资料库会保留。")
                DisclosureGroup("查看错误信息") {
                    Text(errorDescription)
                        .font(.caption)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: 460)
            }
        } actions: {
            Button("重试", action: retry)
                .buttonStyle(.borderedProminent)
        }
    }
}
