import SwiftData
import SwiftUI

struct LibraryView: View {
    let catalog: any MediaCatalogServing
    let posters: any PosterFileManaging
    @Environment(\.modelContext) private var context
    @Query(sort: \ViewingRecord.createdAt, order: .reverse) private var records: [ViewingRecord]
    @State private var model = LibraryViewModel()
    @State private var isShowingAdd = false
    @State private var path: [UUID] = []
    @State private var posterRetry = 0

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 24)]
    nonisolated private struct PosterBatchID: Hashable {
        let records: [UUID]
        let retry: Int
    }

    var body: some View {
        @Bindable var model = model
        let matching = model.matchingRecords(in: records)
        return NavigationStack(path: $path) {
            VStack(spacing: 0) {
                HStack(spacing: 18) {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("搜索已保存的片名", text: $model.searchText)
                            .textFieldStyle(.plain)
                            .accessibilityLabel("搜索已保存的片名")
                        if !model.searchText.isEmpty {
                            Button { model.searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain).help("清除搜索")
                                .accessibilityLabel("清除搜索")
                        }
                    }
                    .padding(8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    Picker("作品类型", selection: $model.mediaFilter) {
                        ForEach(LibraryMediaFilter.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 220)
                }
                .padding(.horizontal, 28).padding(.vertical, 16)
                Divider()
                posterStatus
                libraryContent(matching)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("观影记录")
            .navigationDestination(for: UUID.self) { RecordDetailDestinationView(recordID: $0) }
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Text(matching.count == records.count ? "\(records.count) 部作品" : "显示 \(matching.count) / \(records.count) 部")
                        .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .primaryAction) {
                    SettingsLink { Label("设置", systemImage: "gearshape") }.help("设置")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("添加观影记录", systemImage: "plus") { isShowingAdd = true }
                        .help("添加观影记录").disabled(model.isPreparingLibrary)
                }
            }
            .sheet(isPresented: $isShowingAdd) {
                AddRecordView(catalog: catalog, store: RecordStore(context: context), posters: posters) { id in
                    isShowingAdd = false
                    if path.last != id { path.append(id) }
                }
            }
        }
        .environment(\.posterCache, posters)
        .environment(\.posterReloadVersions, model.posterReloadVersions)
        .task(id: PosterBatchID(records: records.map(\.id), retry: posterRetry)) {
            let targets = records.map { SavedPosterTarget(recordID: $0.id, path: $0.posterPath, filename: $0.posterFilename) }
            await model.cacheSavedPosters(targets, cache: posters, store: RecordStore(context: context))
        }
    }

    @ViewBuilder
    private var posterStatus: some View {
        if let message = model.cleanupMessage {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.callout).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
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
                Text("把看过的电影和剧集留在这里。")
            } actions: {
                Button("添加观影记录", systemImage: "plus") { isShowingAdd = true }
                    .buttonStyle(.borderedProminent).disabled(model.isPreparingLibrary)
            }
        } else if matching.isEmpty {
            ContentUnavailableView {
                Label("没有符合条件的记录", systemImage: "magnifyingglass")
            } description: {
                Text("试试其他片名，或切换电影与剧集筛选。")
            } actions: {
                Button("清除搜索和筛选") { model.resetFilters() }
            }
        } else {
            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                    ForEach(matching) { record in
                        NavigationLink(value: record.id) { RecordCard(record: record) }.buttonStyle(.plain)
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
            HStack {
                Text(record.mediaType.title)
                if let year = record.releaseYear { Text(String(year)) }
                Spacer(minLength: 0)
                Label("\(record.myRating)", systemImage: "star.fill").foregroundStyle(.secondary)
                    .accessibilityLabel("我的评分 \(record.myRating) 分")
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }
}
