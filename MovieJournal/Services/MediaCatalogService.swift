import Foundation

nonisolated protocol MediaCatalogServing: Sendable {
    func search(title: String) async throws -> [MediaSearchResult]
    func details(for candidate: MediaSearchResult) async throws -> MediaDetails
    func supplementalRatings(imdbID: String?) async throws -> SupplementalRatingsResult
}

nonisolated struct MediaCatalogService: MediaCatalogServing {
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
