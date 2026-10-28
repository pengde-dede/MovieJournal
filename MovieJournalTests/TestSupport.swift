import Foundation
@testable import MovieJournal

nonisolated enum StubReply: Sendable {
    case json(String, status: Int = 200)
    case failure(APIError)
}

actor ScriptedTransport: HTTPTransport {
    private var replies: [StubReply]
    private(set) var requests: [URLRequest] = []
    init(_ replies: [StubReply]) { self.replies = replies }
    func send(_ request: URLRequest) async throws -> HTTPResponse {
        requests.append(request)
        guard !replies.isEmpty else { throw APIError.invalidResponse }
        switch replies.removeFirst() {
        case .json(let json, let status): return HTTPResponse(data: Data(json.utf8), statusCode: status)
        case .failure(let error): throw error
        }
    }
}

actor MemoryKeychain: KeychainStoring {
    private var values: [APIKeyProvider: String]
    private(set) var readCount = 0
    init(_ values: [APIKeyProvider: String] = [:]) { self.values = values }
    func contains(_ provider: APIKeyProvider) async throws -> Bool { values[provider] != nil }
    func read(_ provider: APIKeyProvider) async throws -> String? { readCount += 1; return values[provider] }
    func save(_ value: String, for provider: APIKeyProvider) async throws { values[provider] = value }
    func delete(_ provider: APIKeyProvider) async throws { values[provider] = nil }
    func value(_ provider: APIKeyProvider) -> String? { values[provider] }
}

nonisolated enum Fixtures {
    static let movie = MediaSearchResult(tmdbID: 278, mediaType: .movie, title: "肖申克的救赎", originalTitle: "The Shawshank Redemption", releaseYear: 1994, posterPath: "/poster.jpg")
    static let series = MediaSearchResult(tmdbID: 1396, mediaType: .tv, title: "绝命毒师", originalTitle: "Breaking Bad", releaseYear: 2008, posterPath: "/series.jpg")

    static func details(_ candidate: MediaSearchResult = movie) -> MediaDetails {
        MediaDetails(tmdbID: candidate.tmdbID, mediaType: candidate.mediaType, title: candidate.title, originalTitle: candidate.originalTitle, releaseYear: candidate.releaseYear, genres: ["剧情"], overview: "测试简介", overviewLanguage: "zh-CN", creatorNames: ["测试主创"], castNames: ["测试主演"], imdbID: candidate.mediaType == .movie ? "tt0111161" : "tt0903747", tmdbRating: 8.7, imdbRating: nil, rottenTomatoesRating: nil, posterPath: candidate.posterPath, fetchedAt: Date(timeIntervalSince1970: 1_793_034_000), informationNote: nil)
    }

    static func movieJSON(overview: String = "中文简介", votes: Int = 100) throws -> String {
        let cast: [[String: Any]] = (1...6).reversed().map { ["id": $0, "name": "演员\($0)", "order": $0 - 1] }
        let body: [String: Any] = [
            "id": 278, "title": "肖申克的救赎", "original_title": "The Shawshank Redemption",
            "release_date": "1994-09-23", "overview": overview, "genres": [["name": "剧情"]],
            "poster_path": "/poster.jpg", "vote_average": 8.7, "vote_count": votes,
            "imdb_id": "tt0111161", "external_ids": ["imdb_id": "tt0111161"],
            "credits": ["cast": cast, "crew": [["id": 100, "name": "Frank Darabont", "job": "Director"], ["id": 101, "name": "其他工作人员", "job": "Editor"]]]
        ]
        return String(decoding: try JSONSerialization.data(withJSONObject: body), as: UTF8.self)
    }
}
