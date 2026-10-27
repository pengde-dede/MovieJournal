import Foundation

nonisolated enum APIKeyProvider: String, CaseIterable, Identifiable, Sendable {
    case tmdb
    case omdb

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tmdb: "TMDB API Key（v3）"
        case .omdb: "OMDb API Key（可选）"
        }
    }

    var shortName: String {
        switch self {
        case .tmdb: "TMDB"
        case .omdb: "OMDb"
        }
    }

    var explanation: String {
        switch self {
        case .tmdb: "使用 TMDB 官网的 API Key（v3 auth）获取影片资料。"
        case .omdb: "用于补充 IMDb 和烂番茄评分，未填写时这部分评分留空。"
        }
    }

    var account: String { "\(rawValue).api-key" }

    var helpURL: URL? {
        switch self {
        case .tmdb: URL(string: "https://www.themoviedb.org/settings/api")
        case .omdb: URL(string: "https://www.omdbapi.com/apikey.aspx")
        }
    }
}
