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
    let collection: Collection?

    struct Collection: Decodable, Sendable {
        let id: Int
        let name: String?
        let posterPath: String?

        enum CodingKeys: String, CodingKey {
            case id, name
            case posterPath = "poster_path"
        }
    }

    func movieSeriesLookup() throws -> MovieSeriesLookup {
        guard let collection else { return MovieSeriesLookup(series: nil) }
        guard collection.id > 0, let name = collection.name.nonEmpty else { throw APIError.invalidResponse }
        return MovieSeriesLookup(series: MovieSeries(id: collection.id, name: name, posterPath: collection.posterPath.nonEmpty))
    }

    struct Genre: Decodable, Sendable { let name: String? }
    struct Person: Decodable, Sendable {
        let id: Int?
        let name: String?
        let order: Int?
        let job: String?
        let originalName: String?
        let profilePath: String?

        enum CodingKeys: String, CodingKey {
            case id, name, order, job
            case originalName = "original_name", profilePath = "profile_path"
        }
    }
    struct Credits: Decodable, Sendable {
        let id: Int?
        let cast: [Person]?
        let crew: [Person]?

        var movieDirectors: [MovieDirector]? {
            guard let crew else { return nil }
            var seen = Set<Int>()
            return crew.compactMap { person in
                guard person.job == "Director", let id = person.id, id > 0,
                      let name = person.name.nonEmpty ?? person.originalName.nonEmpty,
                      seen.insert(id).inserted else { return nil }
                return MovieDirector(id: id, name: name, originalName: person.originalName.nonEmpty,
                                     profilePath: person.profilePath.nonEmpty)
            }
        }
    }
    struct ExternalIDs: Decodable, Sendable {
        let imdbID: String?
        enum CodingKeys: String, CodingKey { case imdbID = "imdb_id" }
    }
    enum CodingKeys: String, CodingKey {
        case id, title, name, overview, genres, credits
        case collection = "belongs_to_collection"
        case originalTitle = "original_title", originalName = "original_name"
        case releaseDate = "release_date", firstAirDate = "first_air_date", posterPath = "poster_path"
        case voteAverage = "vote_average", voteCount = "vote_count", imdbID = "imdb_id"
        case createdBy = "created_by", aggregateCredits = "aggregate_credits", externalIDs = "external_ids"
    }
}

nonisolated struct TMDBAuthenticationResponse: Decodable, Sendable {
    let success: Bool
}

nonisolated struct TMDBPersonSearchResponse: Decodable, Sendable {
    let results: [Person]

    struct Person: Decodable, Sendable {
        let id: Int
        let name: String?
        let knownForDepartment: String?
        let profilePath: String?
        let knownFor: [TMDBSearchResponse.Item]?

        enum CodingKeys: String, CodingKey {
            case id, name
            case knownForDepartment = "known_for_department", profilePath = "profile_path", knownFor = "known_for"
        }
    }
}

nonisolated struct TMDBCombinedCreditsResponse: Decodable, Sendable {
    let crew: [Credit]?

    struct Credit: Decodable, Sendable {
        let id: Int
        let mediaType: String?
        let title: String?
        let name: String?
        let originalTitle: String?
        let originalName: String?
        let releaseDate: String?
        let firstAirDate: String?
        let posterPath: String?
        let job: String?
        let department: String?

        enum CodingKeys: String, CodingKey {
            case id, title, name, job, department
            case mediaType = "media_type", originalTitle = "original_title", originalName = "original_name"
            case releaseDate = "release_date", firstAirDate = "first_air_date", posterPath = "poster_path"
        }
    }
}
