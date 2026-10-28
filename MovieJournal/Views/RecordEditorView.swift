import SwiftUI

struct RecordEditorView: View {
    @Binding var draft: RecordDraft

    var body: some View {
        GroupBox("我的观影信息") {
            VStack(alignment: .leading, spacing: 16) {
                DatePicker(
                    draft.details.mediaType == .tv ? "最近观看日期" : "观看日期",
                    selection: $draft.watchedOn,
                    displayedComponents: .date
                )
                Picker("我的评分（必填）", selection: $draft.myRating) {
                    Text("请选择").tag(Int?.none)
                    ForEach(1...10, id: \.self) { value in
                        Text("\(value) 分").tag(Optional(value))
                    }
                }
                if draft.details.mediaType == .tv {
                    TextField("看到第几季（必填）", value: $draft.watchedSeason, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                    Text("可以记录正在观看、尚未看完的这一季。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                TextField("一句话短评（可空）", text: $draft.shortReview, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                if let message = draft.validationMessage {
                    Text(message).font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(8)
        }
    }
}
