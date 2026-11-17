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
    var trial: TrialCatalogAccess? = nil

    init(keychain: any KeychainStoring, tmdb: TMDBClient = TMDBClient(), omdb: OMDbClient = OMDbClient(), trial: TrialCatalogAccess? = nil) {
        self.keychain = keychain
        self.tmdb = tmdb
        self.omdb = omdb
        self.trial = trial
    }

    func search(title: String) async throws -> [MediaSearchResult] {
        let (client, credential) = try await catalogAccess()
        return try await client.search(title: title, key: credential)
    }

    func details(for candidate: MediaSearchResult) async throws -> MediaDetails {
        let (client, credential) = try await catalogAccess()
        return try await client.details(for: candidate, key: credential)
    }

    func movieSeries(tmdbID: Int) async throws -> MovieSeriesLookup {
        let (client, credential) = try await catalogAccess()
        return try await client.movieSeries(tmdbID: tmdbID, key: credential)
    }

    func movieDirectors(tmdbID: Int) async throws -> [MovieDirector] {
        let (client, credential) = try await catalogAccess()
        return try await client.movieDirectors(tmdbID: tmdbID, key: credential)
    }

    func searchPeople(name: String) async throws -> [PersonSearchResult] {
        let (client, credential) = try await catalogAccess()
        return try await client.searchPeople(name: name, key: credential)
    }

    func directedWorks(personID: Int) async throws -> [CreditedWork] {
        let (client, credential) = try await catalogAccess()
        return try await client.directedWorks(personID: personID, key: credential)
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

    private func catalogAccess() async throws -> (TMDBClient, String) {
        if let selected = try await trial?.selectedCatalog() { return selected }
        guard let key = try await keychain.read(.tmdb).nonEmpty else { throw APIError.missingKey(.tmdb) }
        return (tmdb, key)
    }
}
