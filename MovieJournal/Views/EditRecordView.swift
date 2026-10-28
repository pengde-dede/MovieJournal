import SwiftUI

struct EditRecordView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: EditRecordViewModel

    init(record: ViewingRecord, store: RecordStore) {
        _model = State(initialValue: EditRecordViewModel(record: record, store: store))
    }

    var body: some View {
        @Bindable var model = model
        return VStack(spacing: 0) {
            HStack {
                Text("编辑观影记录").font(.title2.bold())
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(model.draft.details.title).font(.title3.bold())
                    RecordEditorView(draft: $model.draft)
                    if let error = model.saveError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
                .padding(24)
            }
            Divider()
            HStack {
                Spacer()
                Button("保存修改") { if model.save() { dismiss() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.didSave || model.draft.validationMessage != nil)
            }
            .padding(20)
        }
        .frame(width: 600, height: 600)
    }
}
