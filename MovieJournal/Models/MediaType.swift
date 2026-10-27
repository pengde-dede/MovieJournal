import Foundation

nonisolated enum MediaType: String, Codable, CaseIterable, Identifiable, Sendable {
    case movie
    case tv

    var id: String { rawValue }

    var title: String {
        switch self {
        case .movie: "电影"
        case .tv: "剧集"
        }
    }

    var systemImage: String {
        switch self {
        case .movie: "film"
        case .tv: "tv"
        }
    }

    func mediaKey(tmdbID: Int) -> String {
        "\(rawValue):\(tmdbID)"
    }
}
