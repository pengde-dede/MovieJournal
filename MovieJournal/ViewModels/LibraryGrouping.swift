import Foundation

nonisolated enum LibraryDisplayMode: String, CaseIterable, Identifiable {
    case works = "单部作品"
    case series = "按系列"
    case directors = "按导演"

    var id: Self { self }
}

nonisolated enum LibraryDestination: Hashable {
    case record(UUID)
    case series(Int)
    case director(Int)
}

struct LibraryGroup {
    let id: LibraryDestination
    let name: String
    let artworkPath: String?
    let records: [ViewingRecord]
    let libraryCount: Int
    let posterSources: [ViewingRecord]

    var usesProfile: Bool {
        if case .director = id { return true }
        return false
    }

    var symbolName: String { usesProfile ? "person.crop.circle" : "film.stack" }

    var chronologicalRecords: [ViewingRecord] { LibrarySort.releaseOldest.sortByTitleOrRelease(records) }
}

enum LibraryTile: Identifiable {
    case record(ViewingRecord)
    case group(LibraryGroup)

    var id: LibraryDestination {
        switch self {
        case .record(let record): .record(record.id)
        case .group(let group): group.id
        }
    }
}

struct LibraryGrouping {
    private struct Membership {
        let id: LibraryDestination
        let name: String
        let artworkPath: String?
    }

    private var groupsByRecord: [UUID: [LibraryDestination]] = [:]
    private var members: [LibraryDestination: [ViewingRecord]] = [:]
    private var metadata: [LibraryDestination: Membership] = [:]

    init(records: [ViewingRecord], mode: LibraryDisplayMode) {
        guard mode != .works else { return }
        for record in records {
            for group in Self.memberships(for: record, mode: mode) {
                groupsByRecord[record.id, default: []].append(group.id)
                members[group.id, default: []].append(record)
                if metadata[group.id] == nil || (metadata[group.id]?.artworkPath == nil && group.artworkPath != nil) {
                    metadata[group.id] = group
                }
            }
        }
    }

    func records(in group: LibraryDestination) -> [ViewingRecord] { members[group] ?? [] }

    func group(_ id: LibraryDestination, matching: [ViewingRecord]) -> LibraryGroup? {
        guard let info = metadata[id], let libraryRecords = members[id], !matching.isEmpty else { return nil }
        let posters = libraryRecords.lazy.filter { $0.posterFilename != nil || $0.posterPath != nil }.prefix(4)
        return LibraryGroup(id: id, name: info.name, artworkPath: info.artworkPath, records: matching,
                            libraryCount: libraryRecords.count, posterSources: Array(posters))
    }

    func tiles(matching: [ViewingRecord]) -> [LibraryTile] {
        guard !groupsByRecord.isEmpty else { return matching.map(LibraryTile.record) }
        var visible: [LibraryDestination: [ViewingRecord]] = [:]
        for record in matching {
            for id in groupsByRecord[record.id] ?? [] where (members[id]?.count ?? 0) >= 2 {
                visible[id, default: []].append(record)
            }
        }
        var displayed = Set<LibraryDestination>()
        return matching.flatMap { record -> [LibraryTile] in
            let eligible = (groupsByRecord[record.id] ?? []).filter { visible[$0] != nil }
            guard !eligible.isEmpty else { return [.record(record)] }
            return eligible.compactMap { id in
                guard displayed.insert(id).inserted, let records = visible[id],
                      let group = group(id, matching: records) else { return nil }
                return .group(group)
            }
        }
    }

    private static func memberships(for record: ViewingRecord, mode: LibraryDisplayMode) -> [Membership] {
        switch mode {
        case .works: return []
        case .series:
            guard let series = record.movieSeries else { return [] }
            return [Membership(id: .series(series.id), name: series.name,
                               artworkPath: TMDBImageURL.poster(series.posterPath) == nil ? nil : series.posterPath)]
        case .directors:
            return (record.movieDirectors ?? []).map { director in
                Membership(id: .director(director.id), name: director.name,
                           artworkPath: TMDBImageURL.profile(director.profilePath) == nil ? nil : director.profilePath)
            }
        }
    }
}
