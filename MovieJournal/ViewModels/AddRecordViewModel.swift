import Foundation
import Observation

@MainActor
@Observable
final class AddRecordViewModel {
    var query = ""
    private(set) var results: [MediaSearchResult] = []
    private(set) var hasSearched = false
    private(set) var isSearching = false
    private(set) var searchError: String?
    private(set) var selectedResult: MediaSearchResult?
    private(set) var isLoadingDetails = false
    private(set) var detailsError: String?
    var draft: RecordDraft?
    private(set) var duplicateRecordID: UUID?
    private(set) var saveError: String?
    private(set) var isSaving = false
    private(set) var isLoadingSupplemental = false
    private(set) var supplementalMessage: String?

    private let catalog: any MediaCatalogServing
    private let store: RecordStore
    private var searchRevision = 0
    private var selectionRevision = 0
    private var savedRecordID: UUID?
    @ObservationIgnored private(set) var searchTask: Task<Void, Never>?
    @ObservationIgnored private(set) var detailsTask: Task<Void, Never>?
    @ObservationIgnored private(set) var supplementalTask: Task<Void, Never>?

    init(catalog: any MediaCatalogServing, store: RecordStore) {
        self.catalog = catalog
        self.store = store
    }

    @discardableResult
    func search() -> Task<Void, Never> {
        cancelPendingWork()
        selectedResult = nil
        draft = nil
        duplicateRecordID = nil
        detailsError = nil
        saveError = nil
        results = []
        hasSearched = true
        let title = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            searchError = "请输入电影或剧集的片名。"
            return Task {}
        }
        let revision = searchRevision
        searchError = nil
        isSearching = true
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let results = try await catalog.search(title: title)
                guard !Task.isCancelled, revision == searchRevision else { return }
                self.results = results
                isSearching = false
            } catch {
                guard !Task.isCancelled, revision == searchRevision else { return }
                isSearching = false
                if !(error is CancellationError) { searchError = error.localizedDescription }
            }
        }
        searchTask = task
        return task
    }

    @discardableResult
    func select(_ candidate: MediaSearchResult) -> Task<Void, Never> {
        selectionRevision += 1
        detailsTask?.cancel()
        supplementalTask?.cancel()
        isLoadingSupplemental = false
        supplementalMessage = nil
        selectedResult = candidate
        draft = nil
        duplicateRecordID = nil
        detailsError = nil
        saveError = nil
        isLoadingDetails = false
        do {
            if let existing = try store.existingRecord(tmdbID: candidate.tmdbID, mediaType: candidate.mediaType) {
                duplicateRecordID = existing.id
                return Task {}
            }
        } catch {
            detailsError = "无法检查已有记录：\(error.localizedDescription)"
            return Task {}
        }
        isLoadingDetails = true
        let revision = selectionRevision
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let details = try await catalog.details(for: candidate)
                guard !Task.isCancelled, revision == selectionRevision else { return }
                draft = RecordDraft(details: details)
                isLoadingDetails = false
                loadSupplemental(imdbID: details.imdbID, revision: revision)
            } catch {
                guard !Task.isCancelled, revision == selectionRevision else { return }
                isLoadingDetails = false
                if !(error is CancellationError) { detailsError = error.localizedDescription }
            }
        }
        detailsTask = task
        return task
    }

    func saveRecord() -> UUID? {
        guard savedRecordID == nil, !isSaving, let draft else { return nil }
        saveError = nil
        isSaving = true
        do {
            let record = try draft.makeRecord()
            try store.insert(record)
            savedRecordID = record.id
            supplementalTask?.cancel()
            return record.id
        } catch RecordStore.SaveError.duplicate(let id) {
            duplicateRecordID = id
            isSaving = false
            return nil
        } catch {
            saveError = error.localizedDescription
            isSaving = false
            return nil
        }
    }

    func cancelPendingWork() {
        searchRevision += 1
        selectionRevision += 1
        searchTask?.cancel()
        detailsTask?.cancel()
        supplementalTask?.cancel()
        isSearching = false
        isLoadingDetails = false
        isLoadingSupplemental = false
    }

    private func loadSupplemental(imdbID: String?, revision: Int) {
        isLoadingSupplemental = true
        supplementalTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await catalog.supplementalRatings(imdbID: imdbID)
                guard !Task.isCancelled, revision == selectionRevision, !isSaving, draft != nil else { return }
                isLoadingSupplemental = false
                switch result {
                case .loaded(let ratings):
                    draft?.details.imdbRating = ratings.imdb
                    draft?.details.rottenTomatoesRating = ratings.rottenTomatoes
                    supplementalMessage = ratings.imdb == nil && ratings.rottenTomatoes == nil ? "OMDb 暂无补充评分，可以直接保存。" : nil
                case .notConfigured:
                    supplementalMessage = "未配置 OMDb Key，补充评分留空。"
                case .noIMDbID:
                    supplementalMessage = "TMDB 未提供 IMDb 编号，补充评分留空。"
                case .unavailable(let message):
                    supplementalMessage = "\(message) 补充评分暂时留空，仍可保存。"
                }
            } catch {
                guard !Task.isCancelled, revision == selectionRevision else { return }
                isLoadingSupplemental = false
                if !(error is CancellationError) { supplementalMessage = "补充评分暂不可用，仍可保存。" }
            }
        }
    }
}
