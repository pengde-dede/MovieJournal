import SwiftUI

@MainActor
enum RecordDraftBinding {
    static func make(_ source: Binding<RecordDraft?>) -> Binding<RecordDraft>? {
        guard let snapshot = source.wrappedValue else { return nil }
        // 移除表单时，SwiftUI / 输入法仍可能读取旧 Binding；保留安全的只读快照。
        return Binding(
            get: {
                guard let current = source.wrappedValue, current.editingID == snapshot.editingID else {
                    return snapshot
                }
                return current
            },
            set: { updated in
                // 搜索或选择作品后，旧表单不能恢复草稿，也不能覆盖新的编辑。
                guard source.wrappedValue?.editingID == snapshot.editingID else { return }
                source.wrappedValue = updated
            }
        )
    }
}
