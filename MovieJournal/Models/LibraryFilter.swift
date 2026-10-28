import Foundation

nonisolated enum LibraryMediaFilter: String, CaseIterable, Identifiable, Sendable {
    case all, movie, tv
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "全部"
        case .movie: "电影"
        case .tv: "剧集"
        }
    }
    func includes(_ type: MediaType) -> Bool {
        self == .all || rawValue == type.rawValue
    }
}
