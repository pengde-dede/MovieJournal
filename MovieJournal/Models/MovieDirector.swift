import Foundation

nonisolated struct MovieDirector: Codable, Equatable, Identifiable, Sendable {
    let id: Int
    let name: String
    let originalName: String?
    let profilePath: String?

    var profileFilename: String? { PosterCache.profileFilename(for: profilePath) }
}

nonisolated enum MovieMetadataKind: String, Hashable, Sendable {
    case series = "系列"
    case directors = "导演"
}

nonisolated enum MovieMetadataLookup: Sendable {
    case series(MovieSeriesLookup)
    case directors([MovieDirector])

    var kind: MovieMetadataKind {
        switch self {
        case .series: .series
        case .directors: .directors
        }
    }

    var hasMatch: Bool {
        switch self {
        case .series(let lookup): lookup.series != nil
        case .directors(let directors): !directors.isEmpty
        }
    }
}
