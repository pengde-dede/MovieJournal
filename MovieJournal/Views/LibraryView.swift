import SwiftData
import SwiftUI

struct LibraryView: View {
    let catalog: any MediaCatalogServing
    @Environment(\.modelContext) private var context
    @Query(sort: \ViewingRecord.createdAt, order: .reverse) private var records: [ViewingRecord]
    @State private var isShowingAdd = false
    @State private var path: [UUID] = []

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 24)]

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if records.isEmpty {
                    ContentUnavailableView {
                        Label("还没有观影记录", systemImage: "film.stack")
                    } description: {
                        Text("把看过的电影和剧集留在这里。")
                    } actions: {
                        Button("添加观影记录", systemImage: "plus") { isShowingAdd = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                            ForEach(records) { record in
                                NavigationLink(value: record.id) { RecordCard(record: record) }
                                    .buttonStyle(.plain)
                            }
                        }
                        .padding(28)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("观影记录")
            .navigationDestination(for: UUID.self) { RecordDetailDestinationView(recordID: $0) }
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Text("\(records.count) 部作品").foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .primaryAction) {
                    SettingsLink { Label("设置", systemImage: "gearshape") }.help("设置")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("添加观影记录", systemImage: "plus") { isShowingAdd = true }
                        .help("添加观影记录")
                }
            }
            .sheet(isPresented: $isShowingAdd) {
                AddRecordView(catalog: catalog, store: RecordStore(context: context)) { id in
                    isShowingAdd = false
                    if path.last != id { path.append(id) }
                }
            }
        }
    }
}

private struct RecordCard: View {
    let record: ViewingRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PosterView(path: record.posterPath)
            Text(record.title).font(.headline).lineLimit(2)
            HStack {
                Text(record.mediaType.title)
                if let year = record.releaseYear { Text(String(year)) }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }
}
