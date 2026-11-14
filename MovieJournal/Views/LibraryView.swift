import SwiftData
import SwiftUI

struct LibraryView: View {
    let catalog: any MediaCatalogServing
    let posters: any PosterFileManaging
    let cleanup: PosterCleanupCoordinator
    @Environment(\.modelContext) private var context
    @Query(sort: \ViewingRecord.createdAt, order: .reverse) private var records: [ViewingRecord]
    @State private var model = LibraryViewModel()
    @State private var statusError: String?
    @State private var showingStatusError = false
    @State private var showingBackup = false
    @State private var isShowingAdd = false
    @State private var addingSession: UUID?
    @State private var path: [UUID] = []
    @State private var posterRetry = 0

    @AppStorage("librarySort") private var sort = LibrarySort.added

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 24)]
    nonisolated private struct PosterBatchID: Hashable {
        let records: [UUID]
        let retry: Int
    }

    var body: some View {
        let matching = model.matchingRecords(in: records, sort: sort)
        return NavigationStack(path: $path) {
            libraryContent(matching)
                .safeAreaInset(edge: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        searchControls
                        statusControls
                        posterStatus
                    }
                }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("观影记录")
            .navigationDestination(for: UUID.self) { RecordDetailDestinationView(recordID: $0, cleanup: cleanup, catalog: catalog) }
            .toolbar {
                ToolbarItem {
                    Menu {
                        Picker("排序", selection: $sort) {
                            ForEach(LibrarySort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        Divider()
                        Button("备份与恢复…") { showingBackup = true }
                    } label: { Label("资料库选项", systemImage: "ellipsis.circle") }
                    .help("排序、备份与恢复")
                }
                ToolbarItem(placement: .automatic) {
                    Text(matching.count == records.count ? "\(records.count) 部作品" : "显示 \(matching.count) / \(records.count) 部")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                }
                ToolbarItem(placement: .primaryAction) {
                    SettingsLink { Label("设置", systemImage: "gearshape") }.help("设置")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("添加观影记录", systemImage: "plus") { showAdd() }
                        .help("添加观影记录").disabled(model.isPreparingLibrary || cleanup.isCleaning)
                }
            }
            .sheet(isPresented: $showingBackup) {
                BackupView(context: context, posters: posters, cleanup: cleanup)
            }
            .sheet(isPresented: $isShowingAdd, onDismiss: finishAdding) {
                AddRecordView(catalog: catalog, store: RecordStore(context: context), posters: posters) { id in
                    isShowingAdd = false
                    if path.last != id { path.append(id) }
                }
            }
        }
        .alert("状态未能保存", isPresented: $showingStatusError) {
            Button("好", role: .cancel) {}
        } message: { Text(statusError ?? "请稍后重试。") }
        .onDisappear { finishAdding() }
        .environment(\.posterCache, posters)
        .environment(\.posterReloadVersions, model.posterReloadVersions)
        .task(id: PosterBatchID(records: records.map(\.id), retry: posterRetry)) {
            let targets = records.map { SavedPosterTarget(recordID: $0.id, path: $0.posterPath, filename: $0.posterFilename) }
            await model.cacheSavedPosters(targets, cache: posters, store: RecordStore(context: context), cleanup: cleanup)
        }
    }

    @AppStorage(LibraryGlassStyle.styleKey) private var glassStyle = LibraryGlassStyle.regular
    @AppStorage(LibraryGlassStyle.tintKey) private var tint = LibraryGlassStyle.defaultTint

    private var searchControls: some View {
        @Bindable var model = model
        return HStack(spacing: 18) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索片名、导演或主演", text: $model.searchText)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("搜索片名、导演或主演")
                if !model.searchText.isEmpty {
                    Button { model.searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).help("清除搜索")
                        .accessibilityLabel("清除搜索")
                }
            }
            .padding(.leading, 5)
            Divider().frame(height: 20)
            Picker("作品类型", selection: $model.mediaFilter) {
                ForEach(LibraryMediaFilter.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background { LibraryGlassSurface(style: glassStyle, tint: tint).allowsHitTesting(false) }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }

    private var statusControls: some View {
        @Bindable var model = model
        return Picker("观看状态筛选", selection: $model.statusFilter) {
            ForEach(LibraryStatusFilter.allCases) { filter in
                let count = records.filter { filter.includes($0.watchStatus) }.count
                Text("\(filter.title) \(count)").tag(filter)
            }
        }
        .pickerStyle(.segmented).labelsHidden()
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24).padding(.bottom, 10)
    }

    private func changeStatus(_ status: WatchStatus, record: ViewingRecord) {
        do { try RecordStore(context: context).setWatchStatus(status, recordID: record.id) }
        catch { statusError = error.localizedDescription; showingStatusError = true }
    }

    private func showAdd() {
        guard !model.isPreparingLibrary, addingSession == nil, let session = cleanup.beginAdding() else { return }
        addingSession = session
        isShowingAdd = true
    }

    private func finishAdding() {
        guard let session = addingSession else { return }
        addingSession = nil
        cleanup.finishAdding(session, store: RecordStore(context: context))
    }

    @ViewBuilder
    private var posterStatus: some View {
        if let message = cleanup.cleanupMessage {
            HStack(alignment: .top, spacing: 12) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("重试海报清理") { cleanup.requestCleanup(store: RecordStore(context: context)) }
                    .disabled(cleanup.isCleaning)
            }
            .padding(.horizontal, 28).padding(.vertical, 10)
        }
        if cleanup.isCleaning {
            HStack {
                ProgressView().controlSize(.small)
                Text("正在清理未使用的海报…")
                Spacer()
            }
            .font(.callout).foregroundStyle(.secondary)
            .padding(.horizontal, 28).padding(.vertical, 10)
        }
        if model.isCachingPosters {
            HStack {
                ProgressView().controlSize(.small)
                Text("正在保存海报到本机（\(model.completedPosters)/\(model.totalPosters)）…")
                Spacer()
            }
            .font(.callout).foregroundStyle(.secondary)
            .padding(.horizontal, 28).padding(.vertical, 10)
        } else if let message = model.posterMessage {
            HStack(alignment: .top, spacing: 12) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("重试海报") { posterRetry += 1 }
            }
            .padding(.horizontal, 28).padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private func libraryContent(_ matching: [ViewingRecord]) -> some View {
        if records.isEmpty {
            ContentUnavailableView {
                Label("还没有观影记录", systemImage: "film.stack")
            } description: {
                Text("收藏想看的电影和剧集，记录观看进度与感受。")
            } actions: {
                Button("添加观影记录", systemImage: "plus") { showAdd() }
                    .buttonStyle(.borderedProminent).disabled(model.isPreparingLibrary || cleanup.isCleaning)
            }
        } else if matching.isEmpty {
            ContentUnavailableView {
                Label("没有符合条件的记录", systemImage: "magnifyingglass")
            } description: {
                Text("试试其他片名或人名（欧美影人多为英文名），或切换作品类型和观看状态。")
            } actions: {
                Button("清除搜索和筛选") { model.resetFilters() }
            }
        } else {
            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                    ForEach(matching) { record in
                        NavigationLink(value: record.id) { RecordCard(record: record) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                ForEach(WatchStatus.allCases) { status in
                                    Button { changeStatus(status, record: record) } label: {
                                        Label("标为\(status.title)", systemImage: status.systemImage)
                                    }.disabled(record.watchStatus == status)
                                }
                            }
                    }
                }
                .padding(28)
            }
        }
    }
}

private struct RecordCard: View {
    let record: ViewingRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PosterView(path: record.posterPath, filename: record.posterFilename)
            Text(record.title).font(.headline).lineLimit(2)
            Label(record.watchStatus.title, systemImage: record.watchStatus.systemImage)
                .font(.caption.weight(.medium))
                .foregroundStyle(record.watchStatus == .watching ? Color.accentColor : Color.secondary)
            HStack {
                Text(record.mediaType.title)
                if let year = record.releaseYear { Text(String(year)) }
                Spacer(minLength: 0)
                if let rating = record.myRating {
                    Label("\(rating)", systemImage: "star.fill")
                        .accessibilityLabel("我的评分 \(rating) 分")
                } else {
                    Text("未评分")
                }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }
}
