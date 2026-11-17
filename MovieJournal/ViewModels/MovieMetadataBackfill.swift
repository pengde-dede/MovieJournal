import Foundation
import Observation

// 应用内所有窗口共用一次补全任务，避免重复向 TMDB 请求同一部电影。
@MainActor
@Observable
final class MovieMetadataBackfill {
    private(set) var runningKind: MovieMetadataKind?
    var isRunning: Bool { runningKind != nil }
    private(set) var completed = 0
    private(set) var total = 0
    private(set) var messages: [MovieMetadataKind: String] = [:]
    private var task: Task<Void, Never>?

    @discardableResult
    func startSeries(store: RecordStore, catalog: any MovieSeriesCatalogServing) -> Task<Void, Never>? {
        start(.series, store: store) { .series(try await catalog.movieSeries(tmdbID: $0)) }
    }

    @discardableResult
    func startDirectors(store: RecordStore, catalog: any MovieDirectorCatalogServing) -> Task<Void, Never>? {
        start(.directors, store: store) { .directors(try await catalog.movieDirectors(tmdbID: $0)) }
    }

    private func start(_ kind: MovieMetadataKind, store: RecordStore,
                       fetch: @escaping @Sendable (Int) async throws -> MovieMetadataLookup) -> Task<Void, Never>? {
        guard !isRunning else { return nil }
        let targets: [(id: UUID, tmdbID: Int)]
        do {
            targets = try store.recordsNewestFirst().filter { $0.needsLookup(kind) }.map { ($0.id, $0.tmdbID) }
        } catch {
            messages[kind] = "无法读取待补全的电影。\(error.localizedDescription)"
            return nil
        }
        guard !targets.isEmpty else { messages[kind] = "片库里的电影已检查完毕。"; return nil }
        total = targets.count
        completed = 0
        messages[kind] = nil
        runningKind = kind
        let task = Task { [weak self] in
            guard let self else { return }
            defer { runningKind = nil; self.task = nil }
            var grouped = 0
            var standalone = 0
            var failed = 0
            var firstError: String?
            for target in targets {
                do {
                    try Task.checkCancellation()
                    let lookup = try await fetch(target.tmdbID)
                    try Task.checkCancellation()
                    if try store.saveMovieMetadata(lookup, recordID: target.id, tmdbID: target.tmdbID) {
                        if lookup.hasMatch { grouped += 1 } else { standalone += 1 }
                    }
                } catch is CancellationError {
                    messages[kind] = "已停止补全，已保存 \(grouped + standalone) 部电影的查询结果。"
                    return
                } catch {
                    let apiError = error as? APIError
                    guard apiError == .notFound || apiError == .invalidResponse else {
                        messages[kind] = "已保存 \(grouped + standalone) 部电影的查询结果。\(error.localizedDescription)"
                        return
                    }
                    failed += 1
                    if firstError == nil { firstError = error.localizedDescription }
                }
                completed += 1
            }
            let summary = "已匹配 \(grouped) 部，\(standalone) 部没有\(kind.rawValue)资料。"
            messages[kind] = firstError.map { "\(summary) \(failed) 部可重试。\($0)" } ?? summary
        }
        self.task = task
        return task
    }

    func cancel() { task?.cancel() }
}
