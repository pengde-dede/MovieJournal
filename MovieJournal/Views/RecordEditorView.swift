import SwiftUI

struct RecordEditorView: View {
    @Binding var draft: RecordDraft
    var isRewatch = false
    @State private var fallbackDate = Date.now

    var body: some View {
        GroupBox("我的观影信息") {
            VStack(alignment: .leading, spacing: 16) {
                if !isRewatch {
                    Picker("观看状态", selection: Binding(get: { draft.watchStatus }, set: { draft.changeStatus(to: $0) })) {
                        ForEach(WatchStatus.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text("先加入想看片单，开始观看或看完后再切换状态。已有评分和观看记录会保留。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Picker("我的评分（可选）", selection: $draft.myRating) {
                    Text("暂不评分").tag(Int?.none)
                    ForEach(1...10, id: \.self) { value in
                        Text("\(value) 分").tag(Optional(value))
                    }
                }
                Toggle("记录观看日期", isOn: Binding(
                    get: { draft.watchedOn != nil },
                    set: { draft.watchedOn = $0 ? fallbackDate : nil }
                ))
                if draft.watchedOn != nil {
                    DatePicker(
                        draft.details.mediaType == .tv ? "最近观看日期" : "观看日期",
                        selection: Binding(get: { draft.watchedOn ?? fallbackDate }, set: { draft.watchedOn = $0 }),
                        displayedComponents: .date
                    )
                }
                if draft.details.mediaType == .tv {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("看到第几季（可选）")
                        TextField("例如：2（只填写数字）", text: $draft.watchedSeasonText)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("看到第几季")
                        Text("可以稍后补充；填写时只需输入大于 0 的整数。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                TextField("一句话短评或想看理由（可空）", text: $draft.shortReview, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                if let message = draft.validationMessage {
                    Text(message).font(.callout).foregroundStyle(.orange)
                }
            }
            .padding(8)
        }
    }
}
