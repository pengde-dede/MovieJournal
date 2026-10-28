import SwiftData
import SwiftUI

struct RecordDetailDestinationView: View {
    @Query private var records: [ViewingRecord]
    @Environment(\.dismiss) private var dismiss
    let cleanup: PosterCleanupCoordinator

    init(recordID: UUID, cleanup: PosterCleanupCoordinator) {
        let identifier = recordID
        _records = Query(filter: #Predicate<ViewingRecord> { $0.id == identifier })
        self.cleanup = cleanup
    }

    var body: some View {
        if let record = records.first {
            RecordDetailView(record: record, cleanup: cleanup)
        } else {
            ContentUnavailableView {
                Label("这条记录已不存在", systemImage: "film")
            } description: {
                Text("记录可能已在其他窗口中删除。")
            } actions: {
                Button("返回资料库") { dismiss() }
            }
        }
    }
}

struct RecordDetailView: View {
    let record: ViewingRecord
    let cleanup: PosterCleanupCoordinator
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var model = RecordDetailViewModel()
    @State private var isEditing = false

    var body: some View {
        @Bindable var model = model
        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let error = model.deleteError {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                }
                MediaInformationView(details: MediaDetails(record: record), posterFilename: record.posterFilename)
                GroupBox("我的观影记录") {
                    VStack(alignment: .leading, spacing: 14) {
                        LabeledContent(record.mediaType == .tv ? "最近观看日期" : "观看日期") {
                            Text(record.watchedOn, format: .dateTime.year().month().day())
                        }
                        LabeledContent("我的评分", value: "\(record.myRating)/10")
                        if record.mediaType == .tv, let season = record.watchedSeason {
                            LabeledContent("观看进度", value: "看到第 \(season) 季")
                        }
                        Divider()
                        Text(record.shortReview.isEmpty ? "暂无短评" : record.shortReview)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(8)
                }
            }
            .frame(maxWidth: 1000)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(record.title)
        .textSelection(.enabled)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("编辑", systemImage: "pencil") { isEditing = true }.help("编辑观影记录")
            }
            ToolbarItem(placement: .primaryAction) {
                Button("删除", systemImage: "trash", role: .destructive) {
                    model.requestDeletion(id: record.id, title: record.title)
                }
                .help("删除观影记录")
            }
        }
        .sheet(isPresented: $isEditing) {
            EditRecordView(record: record, store: RecordStore(context: context))
        }
        .alert("删除观影记录？", isPresented: $model.isShowingDeleteConfirmation, presenting: model.deletionRequest) { _ in
            Button("取消", role: .cancel) { model.cancelDeletion() }
            Button("删除记录", role: .destructive) {
                if model.confirmDeletion(store: RecordStore(context: context), cleanup: cleanup) { dismiss() }
            }
        } message: { request in
            Text("将删除《\(request.title)》的观看日期、个人评分和短评。删除后无法恢复。")
        }
    }
}
