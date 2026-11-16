import Foundation

nonisolated enum LibraryDisplayMode: String, CaseIterable, Identifiable {
    case works = "单部作品"
    case series = "按系列"

    var id: Self { self }
}

nonisolated enum LibraryDestination: Hashable {
    case record(UUID)
    case series(Int)
}

struct MovieSeriesGroup: Identifiable {
    let series: MovieSeries
    let records: [ViewingRecord]
    let libraryCount: Int
    let posterSources: [ViewingRecord]

    var id: Int { series.id }
    var chronologicalRecords: [ViewingRecord] { LibrarySort.releaseOldest.sortByTitleOrRelease(records) }

    init?(members: [ViewingRecord], visible: [ViewingRecord]) {
        let metadata = members.compactMap(\.movieSeries)
        guard let first = metadata.first else { return nil }
        series = metadata.first { TMDBImageURL.poster($0.posterPath) != nil } ?? first
        records = visible
        libraryCount = members.count
        posterSources = Array(members.lazy.filter { $0.posterFilename != nil || $0.posterPath != nil }.prefix(4))
    }
}

enum LibraryTile: Identifiable {
    case record(ViewingRecord)
    case series(MovieSeriesGroup)

    var id: LibraryDestination {
        switch self {
        case .record(let record): .record(record.id)
        case .series(let group): .series(group.id)
        }
    }
}

extension LibraryViewModel {
    func seriesTiles(matching: [ViewingRecord], in library: [ViewingRecord]) -> [LibraryTile] {
        let allBySeries = Dictionary(grouping: library, by: \.seriesID)
        let matchesBySeries = Dictionary(grouping: matching, by: \.seriesID)
        var displayed = Set<Int>()
        return matching.compactMap { record in
            guard let id = record.seriesID, let members = allBySeries[id], members.count >= 2,
                  let groupMembers = matchesBySeries[id] else { return .record(record) }
            guard displayed.insert(id).inserted else { return nil }
            guard let group = MovieSeriesGroup(members: members, visible: groupMembers) else { return .record(record) }
            return .series(group)
        }
    }
}
