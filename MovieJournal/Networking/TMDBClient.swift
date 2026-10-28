import Foundation

nonisolated struct TMDBClient: Sendable {
    let transport: any HTTPTransport

    init(transport: any HTTPTransport = HTTPClient()) { self.transport = transport }

    func authenticate(key: String) async throws {
        let request = try request(path: "/3/authentication", key: key)
        let response = try await transport.send(request)
        try APIRequest.check(response, provider: .tmdb)
        let result = try APIRequest.decode(TMDBAuthenticationResponse.self, from: response.data)
        guard result.success else { throw APIError.invalidKey(.tmdb) }
    }

    func search(title: String, key: String) async throws -> [MediaSearchResult] {
        let request = try request(path: "/3/search/multi", key: key, query: [
            URLQueryItem(name: "query", value: title),
            URLQueryItem(name: "language", value: "zh-CN"),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "include_adult", value: "false")
        ])
        let response = try await transport.send(request)
        try APIRequest.check(response, provider: .tmdb)
        let decoded = try APIRequest.decode(TMDBSearchResponse.self, from: response.data)
        return decoded.results.compactMap { item in
            guard item.id > 0, let type = MediaType(rawValue: item.mediaType ?? "") else { return nil }
            let original = type == .movie ? item.originalTitle : item.originalName
            let title = (type == .movie ? item.title : item.name).nonEmpty ?? original.nonEmpty ?? "未命名作品"
            return MediaSearchResult(
                tmdbID: item.id, mediaType: type, title: title,
                originalTitle: original.nonEmpty ?? title,
                releaseYear: Self.year(type == .movie ? item.releaseDate : item.firstAirDate),
                posterPath: item.posterPath
            )
        }
    }

    func details(for candidate: MediaSearchResult, key: String) async throws -> MediaDetails {
        let path = "/3/\(candidate.mediaType.rawValue)/\(candidate.tmdbID)"
        let append = candidate.mediaType == .movie ? "credits,external_ids" : "aggregate_credits,external_ids"
        let request = try request(path: path, key: key, query: [
            URLQueryItem(name: "language", value: "zh-CN"),
            URLQueryItem(name: "append_to_response", value: append)
        ])
        let response = try await transport.send(request)
        try APIRequest.check(response, provider: .tmdb)
        let body = try APIRequest.decode(TMDBDetailsResponse.self, from: response.data)
        guard body.id == candidate.tmdbID else { throw APIError.invalidResponse }
        var overview = body.overview.nonEmpty ?? ""
        var overviewLanguage = "zh-CN"
        var note: String?
        if overview.isEmpty {
            do {
                let englishRequest = try self.request(path: path, key: key, query: [URLQueryItem(name: "language", value: "en-US")])
                let englishResponse = try await transport.send(englishRequest)
                try APIRequest.check(englishResponse, provider: .tmdb)
                let english = try APIRequest.decode(TMDBDetailsResponse.self, from: englishResponse.data)
                overview = english.overview.nonEmpty ?? ""
                if !overview.isEmpty { overviewLanguage = "en" }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                note = "英文简介暂时未能获取，其余资料可以保存。"
            }
        }
        let isMovie = candidate.mediaType == .movie
        let creators = isMovie ? (body.credits?.crew ?? []).filter { $0.job == "Director" } : (body.createdBy ?? [])
        let cast = (isMovie ? body.credits?.cast : body.aggregateCredits?.cast) ?? []
        let orderedCast = cast.enumerated().sorted {
            let left = $0.element.order ?? Int.max
            let right = $1.element.order ?? Int.max
            return left == right ? $0.offset < $1.offset : left < right
        }.map(\.element)
        let original = (isMovie ? body.originalTitle : body.originalName).nonEmpty ?? candidate.originalTitle
        let title = (isMovie ? body.title : body.name).nonEmpty ?? original
        let average = body.voteAverage.flatMap { (0...10).contains($0) && (body.voteCount ?? 0) > 0 ? $0 : nil }
        return MediaDetails(
            tmdbID: candidate.tmdbID, mediaType: candidate.mediaType,
            title: title, originalTitle: original,
            releaseYear: Self.year(isMovie ? body.releaseDate : body.firstAirDate) ?? candidate.releaseYear,
            genres: (body.genres ?? []).compactMap { $0.name.nonEmpty },
            overview: overview, overviewLanguage: overviewLanguage,
            creatorNames: Self.names(creators), castNames: Array(Self.names(orderedCast).prefix(5)),
            imdbID: body.imdbID.nonEmpty ?? body.externalIDs?.imdbID.nonEmpty,
            tmdbRating: average, imdbRating: nil, rottenTomatoesRating: nil,
            posterPath: body.posterPath ?? candidate.posterPath, fetchedAt: .now, informationNote: note
        )
    }

    private func request(path: String, key: String, query: [URLQueryItem] = []) throws -> URLRequest {
        try APIRequest.get(host: "api.themoviedb.org", path: path, query: [URLQueryItem(name: "api_key", value: key)] + query)
    }

    private static func year(_ date: String?) -> Int? {
        guard let date, date.count >= 4, let year = Int(date.prefix(4)), year > 0 else { return nil }
        return year
    }

    private static func names(_ people: [TMDBDetailsResponse.Person]) -> [String] {
        var seen = Set<String>()
        return people.compactMap { person in
            guard let name = person.name.nonEmpty else { return nil }
            let identifier = person.id.map(String.init) ?? name
            guard seen.insert(identifier).inserted else { return nil }
            return name
        }
    }
}

nonisolated extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}
