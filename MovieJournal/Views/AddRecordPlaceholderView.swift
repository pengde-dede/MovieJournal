import SwiftUI

struct AddRecordPlaceholderView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.tint)
            Text("添加观影记录")
                .font(.title2.bold())
            Text("片名搜索尚未启用。")
                .foregroundStyle(.secondary)
            Button("关闭") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(40)
        .frame(width: 380)
    }
}
