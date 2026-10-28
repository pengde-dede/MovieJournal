import Foundation
import Observation

struct RecordDeletionRequest {
    let id: UUID
    let title: String
}

@MainActor
@Observable
final class RecordDetailViewModel {
    var isShowingDeleteConfirmation = false
    private(set) var deletionRequest: RecordDeletionRequest?
    private(set) var deleteError: String?
    private(set) var isRefreshingRatings = false
    private(set) var ratingsMessage: String?
    private(set) var ratingsRefreshFailed = false
    private var ratingsRevision = 0
    @ObservationIgnored private(set) var ratingsTask: Task<Void, Never>?

    @discardableResult
    func refreshRatings(recordID: UUID, imdbID: String?, catalog: any MediaCatalogServing,
                        store: RecordStore) -> Task<Void, Never> {
        if isRefreshingRatings, let ratingsTask { return ratingsTask }
        ratingsMessage = nil
        ratingsRefreshFailed = false
        guard let identifier = imdbID.nonEmpty else {
            ratingsMessage = "这条记录没有 IMDb 编号，暂时无法获取补充评分。"
            return Task {}
        }
        ratingsRevision += 1
        let revision = ratingsRevision
        isRefreshingRatings = true
        let task = Task { [weak self] in
            guard let self else { return }
            defer {
                if revision == ratingsRevision { isRefreshingRatings = false; ratingsTask = nil }
            }
            do {
                let result = try await catalog.supplementalRatings(imdbID: identifier)
                try Task.checkCancellation()
                guard revision == ratingsRevision else { return }
                switch result {
                case .loaded(let ratings):
                    try store.updateSupplementalRatings(ratings, recordID: recordID, expectedIMDbID: identifier)
                    switch (ratings.imdb, ratings.rottenTomatoes) {
                    case (.some, .some): ratingsMessage = "IMDb 和烂番茄评分已刷新并保存到本机。"
                    case (.some, .none): ratingsMessage = "IMDb 评分已刷新并保存；OMDb 未提供烂番茄评分，原值保留。"
                    case (.none, .some): ratingsMessage = "烂番茄评分已刷新并保存；OMDb 未提供 IMDb 评分，原值保留。"
                    case (.none, .none): ratingsMessage = "OMDb 暂无这部作品的补充评分，原值保留。"
                    }
                case .notConfigured:
                    ratingsRefreshFailed = true
                    ratingsMessage = "请先在设置中填写并保存 OMDb Key，再刷新补充评分。"
                case .noIMDbID:
                    ratingsMessage = "这条记录没有 IMDb 编号，暂时无法获取补充评分。"
                case .unavailable(let message):
                    ratingsRefreshFailed = true
                    ratingsMessage = "补充评分刷新失败：\(message) 原有评分已保留，可以重试。"
                }
            } catch {
                guard !Task.isCancelled, revision == ratingsRevision else { return }
                if !(error is CancellationError) {
                    ratingsRefreshFailed = true
                    ratingsMessage = "补充评分未能更新：\(error.localizedDescription) 原有评分已保留，可以重试。"
                }
            }
        }
        ratingsTask = task
        return task
    }

    func cancelRatingRefresh() {
        ratingsRevision += 1
        ratingsTask?.cancel()
        ratingsTask = nil
        isRefreshingRatings = false
        ratingsMessage = nil
        ratingsRefreshFailed = false
    }

    func requestDeletion(id: UUID, title: String) {
        deleteError = nil
        deletionRequest = RecordDeletionRequest(id: id, title: title)
        isShowingDeleteConfirmation = true
    }

    func cancelDeletion() {
        isShowingDeleteConfirmation = false
        deletionRequest = nil
    }

    func confirmDeletion(store: RecordStore, cleanup: PosterCleanupCoordinator) -> Bool {
        guard let request = deletionRequest else { return false }
        cancelDeletion()
        do {
            try store.delete(recordID: request.id)
            cancelRatingRefresh()
            cleanup.requestCleanup(store: store)
            return true
        } catch {
            deleteError = "删除未能完成：\(error.localizedDescription)"
            return false
        }
    }
}
