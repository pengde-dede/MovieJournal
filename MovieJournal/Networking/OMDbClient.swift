import Foundation

nonisolated struct OMDbResponse: Decodable, Sendable {
    let response: String?
    let error: String?
    let imdbRating: String?
    let ratings: [Rating]?
    struct Rating: Decodable, Sendable {
        let source: String
        let value: String
        enum CodingKeys: String, CodingKey { case source = "Source", value = "Value" }
    }
    enum CodingKeys: String, CodingKey {
        case response = "Response", error = "Error", imdbRating, ratings = "Ratings"
    }
}

nonisolated struct OMDbClient: Sendable {
    let transport: any HTTPTransport
    init(transport: any HTTPTransport = HTTPClient()) { self.transport = transport }

    func ratings(imdbID: String, key: String) async throws -> PlatformRatings {
        let request = try APIRequest.get(host: "www.omdbapi.com", path: "/", query: [
            URLQueryItem(name: "apikey", value: key), URLQueryItem(name: "i", value: imdbID)
        ])
        let response = try await transport.send(request)
        try APIRequest.check(response, provider: .omdb)
        let body = try APIRequest.decode(OMDbResponse.self, from: response.data)
        guard body.response?.lowercased() == "true" else {
            let error = (body.error ?? "").lowercased()
            if error.contains("invalid api key") || error.contains("no api key") { throw APIError.invalidKey(.omdb) }
            if error.contains("limit") { throw APIError.rateLimited(.omdb) }
            if error.contains("not found") { throw APIError.notFound }
            throw APIError.invalidResponse
        }
        let imdbText = body.imdbRating ?? body.ratings?.first { $0.source == "Internet Movie Database" }?.value.components(separatedBy: "/").first
        let imdb = imdbText.flatMap(Double.init).flatMap { (0...10).contains($0) ? $0 : nil }
        let tomatoText = body.ratings?.first { $0.source == "Rotten Tomatoes" }?.value
        let tomatoes = tomatoText.flatMap { Int($0.replacingOccurrences(of: "%", with: "")) }.flatMap { (0...100).contains($0) ? $0 : nil }
        return PlatformRatings(imdb: imdb, rottenTomatoes: tomatoes)
    }
}
