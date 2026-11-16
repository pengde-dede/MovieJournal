import Foundation

nonisolated struct MovieSeries: Codable, Equatable, Sendable, Identifiable {
    let id: Int
    let name: String
    let posterPath: String?
}

// 可选包装区分尚未查询与已确认没有系列的电影。
nonisolated struct MovieSeriesLookup: Codable, Equatable, Sendable {
    let series: MovieSeries?
}
