import Foundation

nonisolated protocol MediaCatalogServing: Sendable {
    func search(title: String) async throws -> [MediaSearchResult]
    func details(for candidate: MediaSearchResult) async throws -> MediaDetails
    func supplementalRatings(imdbID: String?) async throws -> SupplementalRatingsResult
}

// 按导演搜索单独成协议，不支持它的目录服务仍可只按片名搜索。
nonisolated protocol PersonCatalogServing: Sendable {
    func searchPeople(name: String) async throws -> [PersonSearchResult]
    func directedWorks(personID: Int) async throws -> [CreditedWork]
}

nonisolated protocol MovieSeriesCatalogServing: Sendable {
    func movieSeries(tmdbID: Int) async throws -> MovieSeriesLookup
}

nonisolated protocol MovieDirectorCatalogServing: Sendable {
    func movieDirectors(tmdbID: Int) async throws -> [MovieDirector]
}

nonisolated struct MediaCatalogService: MediaCatalogServing, PersonCatalogServing, MovieSeriesCatalogServing, MovieDirectorCatalogServing {
    let keychain: any KeychainStoring
    let tmdb: TMDBClient
    let omdb: OMDbClient

    init(keychain: any KeychainStoring, tmdb: TMDBClient = TMDBClient(), omdb: OMDbClient = OMDbClient()) {
        self.keychain = keychain
        self.tmdb = tmdb
        self.omdb = omdb
    }

    func search(title: String) async throws -> [MediaSearchResult] {
        try await tmdb.search(title: title, key: requiredTMDBKey())
    }

    func details(for candidate: MediaSearchResult) async throws -> MediaDetails {
        try await tmdb.details(for: candidate, key: requiredTMDBKey())
    }

    func movieSeries(tmdbID: Int) async throws -> MovieSeriesLookup {
        try await tmdb.movieSeries(tmdbID: tmdbID, key: requiredTMDBKey())
    }

    func movieDirectors(tmdbID: Int) async throws -> [MovieDirector] {
        try await tmdb.movieDirectors(tmdbID: tmdbID, key: requiredTMDBKey())
    }

    func searchPeople(name: String) async throws -> [PersonSearchResult] {
        try await tmdb.searchPeople(name: name, key: requiredTMDBKey())
    }

    func directedWorks(personID: Int) async throws -> [CreditedWork] {
        try await tmdb.directedWorks(personID: personID, key: requiredTMDBKey())
    }

    func supplementalRatings(imdbID: String?) async throws -> SupplementalRatingsResult {
        guard let imdbID = imdbID.nonEmpty else { return .noIMDbID }
        do {
            guard let key = try await keychain.read(.omdb).nonEmpty else { return .notConfigured }
            return .loaded(try await omdb.ratings(imdbID: imdbID, key: key))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    private func requiredTMDBKey() async throws -> String {
        guard let key = try await keychain.read(.tmdb).nonEmpty else { throw APIError.missingKey(.tmdb) }
        return key
    }
}
