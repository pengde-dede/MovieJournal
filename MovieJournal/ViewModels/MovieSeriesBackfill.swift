import Foundation
import Observation

// 应用内所有窗口共用一次补全任务，避免重复向 TMDB 请求同一部电影。
@MainActor
@Observable
final class MovieSeriesBackfill {
    private(set) var isRunning = false
    private(set) var completed = 0
    private(set) var total = 0
    private(set) var message: String?
    private var task: Task<Void, Never>?

    @discardableResult
    func start(store: RecordStore, catalog: any MovieSeriesCatalogServing) -> Task<Void, Never>? {
        guard !isRunning else { return nil }
        let targets: [(id: UUID, tmdbID: Int)]
        do {
            targets = try store.recordsNewestFirst().filter(\.needsSeriesLookup).map { ($0.id, $0.tmdbID) }
        } catch {
            message = "无法读取待补全的电影。\(error.localizedDescription)"
            return nil
        }
        guard !targets.isEmpty else { message = "片库里的电影已检查完毕。"; return nil }
        total = targets.count
        completed = 0
        message = nil
        isRunning = true
        let task = Task { [weak self] in
            guard let self else { return }
            defer { isRunning = false; self.task = nil }
            var grouped = 0
            var standalone = 0
            var failed = 0
            var firstError: String?
            for target in targets {
                do {
                    try Task.checkCancellation()
                    let lookup = try await catalog.movieSeries(tmdbID: target.tmdbID)
                    try Task.checkCancellation()
                    if try store.saveSeriesLookup(lookup, recordID: target.id, tmdbID: target.tmdbID) {
                        if lookup.series == nil { standalone += 1 } else { grouped += 1 }
                    }
                } catch is CancellationError {
                    message = "已停止补全，已保存 \(grouped + standalone) 部电影的查询结果。"
                    return
                } catch {
                    let apiError = error as? APIError
                    guard apiError == .notFound || apiError == .invalidResponse else {
                        message = "已保存 \(grouped + standalone) 部电影的查询结果。\(error.localizedDescription)"
                        return
                    }
                    failed += 1
                    if firstError == nil { firstError = error.localizedDescription }
                }
                completed += 1
            }
            message = "已匹配 \(grouped) 部，\(standalone) 部没有系列。"
            if let firstError { message = "\(message ?? "") \(failed) 部可重试。\(firstError)" }
        }
        self.task = task
        return task
    }

    func cancel() { task?.cancel() }
}
