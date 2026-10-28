import Foundation

nonisolated struct TMDBSearchResponse: Decodable, Sendable {
    let results: [Item]

    struct Item: Decodable, Sendable {
        let id: Int
        let mediaType: String?
        let title: String?
        let name: String?
        let originalTitle: String?
        let originalName: String?
        let releaseDate: String?
        let firstAirDate: String?
        let posterPath: String?

        enum CodingKeys: String, CodingKey {
            case id, title, name
            case mediaType = "media_type", originalTitle = "original_title", originalName = "original_name"
            case releaseDate = "release_date", firstAirDate = "first_air_date", posterPath = "poster_path"
        }
    }
}

nonisolated struct TMDBDetailsResponse: Decodable, Sendable {
    let id: Int
    let title: String?
    let name: String?
    let originalTitle: String?
    let originalName: String?
    let releaseDate: String?
    let firstAirDate: String?
    let overview: String?
    let genres: [Genre]?
    let posterPath: String?
    let voteAverage: Double?
    let voteCount: Int?
    let imdbID: String?
    let createdBy: [Person]?
    let credits: Credits?
    let aggregateCredits: Credits?
    let externalIDs: ExternalIDs?

    struct Genre: Decodable, Sendable { let name: String? }
    struct Person: Decodable, Sendable {
        let id: Int?
        let name: String?
        let order: Int?
        let job: String?
    }
    struct Credits: Decodable, Sendable {
        let cast: [Person]?
        let crew: [Person]?
    }
    struct ExternalIDs: Decodable, Sendable {
        let imdbID: String?
        enum CodingKeys: String, CodingKey { case imdbID = "imdb_id" }
    }
    enum CodingKeys: String, CodingKey {
        case id, title, name, overview, genres, credits
        case originalTitle = "original_title", originalName = "original_name"
        case releaseDate = "release_date", firstAirDate = "first_air_date", posterPath = "poster_path"
        case voteAverage = "vote_average", voteCount = "vote_count", imdbID = "imdb_id"
        case createdBy = "created_by", aggregateCredits = "aggregate_credits", externalIDs = "external_ids"
    }
}

nonisolated struct TMDBAuthenticationResponse: Decodable, Sendable {
    let success: Bool
}
