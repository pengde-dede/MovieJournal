import SwiftData
import SwiftUI

struct RecordDetailDestinationView: View {
    @Query private var records: [ViewingRecord]
    @Environment(\.dismiss) private var dismiss
    let cleanup: PosterCleanupCoordinator
    let catalog: any MediaCatalogServing

    init(recordID: UUID, cleanup: PosterCleanupCoordinator, catalog: any MediaCatalogServing) {
        let identifier = recordID
        _records = Query(filter: #Predicate<ViewingRecord> { $0.id == identifier })
        self.cleanup = cleanup
        self.catalog = catalog
    }

    var body: some View {
        if let record = records.first {
            RecordDetailView(record: record, cleanup: cleanup, catalog: catalog).id(record.id)
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
    let catalog: any MediaCatalogServing
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var model = RecordDetailViewModel()
    @State private var statusError: String?
    @State private var isRewatch = false
    @State private var isEditing = false

    var body: some View {
        @Bindable var model = model
        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let error = model.deleteError {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                }
                if model.isRefreshingRatings {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("正在刷新 IMDb 和烂番茄评分…")
                    }
                    .foregroundStyle(.secondary)
                } else if let message = model.ratingsMessage {
                    Label(message, systemImage: model.ratingsRefreshFailed ? "exclamationmark.triangle" : "info.circle")
                        .font(.callout)
                        .foregroundStyle(model.ratingsRefreshFailed ? Color.orange : Color.secondary)
                }
                GroupBox("我的观影记录") {
                    VStack(alignment: .leading, spacing: 14) {
                        Picker("观看状态", selection: Binding(get: { record.watchStatus }, set: { status in
                            do {
                                try RecordStore(context: context).setWatchStatus(status, recordID: record.id)
                                statusError = nil
                            } catch { statusError = error.localizedDescription }
                        })) {
                            ForEach(WatchStatus.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        if let statusError {
                            Label(statusError, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                        }
                        LabeledContent(record.mediaType == .tv ? "最近观看日期" : "观看日期") {
                            if let date = record.watchedOn {
                                Text(date, format: .dateTime.year().month().day())
                            } else { Text("未记录").foregroundStyle(.secondary) }
                        }
                        LabeledContent("我的评分", value: record.myRating.map { "\($0)/10" } ?? "暂未评分")
                        if record.mediaType == .tv, let season = record.watchedSeason {
                            LabeledContent("观看进度", value: "看到第 \(season) 季")
                        }
                        Divider()
                        Text(record.shortReview.isEmpty ? "暂无短评" : record.shortReview)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(8)
                }
                ViewingHistory(recordID: record.id)
                MediaInformationView(details: MediaDetails(record: record), posterFilename: record.posterFilename)
            }
            .frame(maxWidth: 1000)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(record.title)
        .textSelection(.enabled)
        .onDisappear { model.cancelRatingRefresh() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("刷新补充评分", systemImage: "arrow.clockwise") {
                    model.refreshRatings(recordID: record.id, imdbID: record.imdbID, catalog: catalog,
                        store: RecordStore(context: context))
                }
                .help("刷新 IMDb 和烂番茄评分")
                .disabled(model.isRefreshingRatings)
            }
            ToolbarItem(placement: .primaryAction) {
                if record.watchStatus == .watched {
                    Button("记录重看", systemImage: "repeat") { isRewatch = true }.help("记录一次重看")
                }
            }
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
        .sheet(isPresented: $isRewatch) {
            EditRecordView(record: record, store: RecordStore(context: context), isRewatch: true)
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
            Text("将删除《\(request.title)》的全部观看历史、个人评分和短评。删除后无法恢复。")
        }
    }
}

private struct ViewingHistory: View {
    @Query private var history: [EarlierViewing]

    init(recordID: UUID) {
        _history = Query(filter: #Predicate<EarlierViewing> { $0.recordID == recordID },
                         sort: \.watchedOn, order: .reverse)
    }

    var body: some View {
        if !history.isEmpty {
            DisclosureGroup("以往观看（\(history.count) 次）") {
                ForEach(history) { item in
                    VStack(alignment: .leading) {
                        HStack {
                            if let date = item.watchedOn {
                                Text(date, format: .dateTime.year().month().day())
                            } else { Text("日期未记录") }
                            Text(item.rating.map { "\($0)/10" } ?? "暂未评分")
                            if let season = item.season { Text("第 \(season) 季") }
                        }
                        if !item.review.isEmpty { Text(item.review) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                }
            }
        }
    }
}
