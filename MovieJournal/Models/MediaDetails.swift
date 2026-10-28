import Foundation

nonisolated struct MediaSearchResult: Identifiable, Equatable, Sendable {
    let tmdbID: Int
    let mediaType: MediaType
    let title: String
    let originalTitle: String
    let releaseYear: Int?
    let posterPath: String?

    var id: String { mediaType.mediaKey(tmdbID: tmdbID) }
}

nonisolated struct PlatformRatings: Equatable, Sendable {
    let imdb: Double?
    let rottenTomatoes: Int?
}

nonisolated struct MediaDetails: Equatable, Sendable {
    var tmdbID: Int
    var mediaType: MediaType
    var title: String
    var originalTitle: String
    var releaseYear: Int?
    var genres: [String]
    var overview: String
    var overviewLanguage: String
    var creatorNames: [String]
    var castNames: [String]
    var imdbID: String?
    var tmdbRating: Double?
    var imdbRating: Double?
    var rottenTomatoesRating: Int?
    var posterPath: String?
    var fetchedAt: Date
    var informationNote: String?
}

nonisolated enum SupplementalRatingsResult: Equatable, Sendable {
    case loaded(PlatformRatings)
    case notConfigured
    case noIMDbID
    case unavailable(String)
}
