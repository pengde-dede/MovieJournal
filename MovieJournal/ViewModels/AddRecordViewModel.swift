import Foundation
import Observation

@MainActor
@Observable
final class AddRecordViewModel {
    enum SearchMode: CaseIterable, Identifiable {
        case title
        case director

        var id: Self { self }
        var title: String {
            switch self {
            case .title: "片名"
            case .director: "导演"
            }
        }
    }

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
    private(set) var searchMode = SearchMode.title
    private(set) var personResults: [PersonSearchResult] = []
    private(set) var selectedPerson: PersonSearchResult?
    private(set) var personWorks: [CreditedWork] = []
    private(set) var isLoadingWorks = false
    private(set) var worksError: String?
    private var savedWorkKeys: Set<String> = []

    private let catalog: any MediaCatalogServing
    private let personCatalog: (any PersonCatalogServing)?
    private let posters: any PosterCaching
    private let store: RecordStore
    private(set) var isLoadingPoster = false
    private(set) var posterMessage: String?
    @ObservationIgnored private(set) var posterTask: Task<Void, Never>?
    private var searchRevision = 0
    private var selectionRevision = 0
    private var savedRecordID: UUID?
    @ObservationIgnored private(set) var searchTask: Task<Void, Never>?
    @ObservationIgnored private(set) var detailsTask: Task<Void, Never>?
    @ObservationIgnored private(set) var supplementalTask: Task<Void, Never>?
    private var worksRevision = 0
    @ObservationIgnored private(set) var worksTask: Task<Void, Never>?

    var canSearchByDirector: Bool { personCatalog != nil }

    init(catalog: any MediaCatalogServing, store: RecordStore, posters: any PosterCaching,
         people: (any PersonCatalogServing)? = nil) {
        self.posters = posters
        self.catalog = catalog
        self.store = store
        // 未单独提供时，由同时支持人物搜索的目录服务（正式的 MediaCatalogService）承担。
        personCatalog = people ?? (catalog as? any PersonCatalogServing)
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
        personResults = []
        backToPeople()
        hasSearched = true
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let mode = searchMode
        guard !text.isEmpty else {
            searchError = mode == .director ? "请输入导演的名字。" : "请输入电影或剧集的片名。"
            return Task {}
        }
        let revision = searchRevision
        searchError = nil
        isSearching = true
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                switch mode {
                case .title:
                    let results = try await catalog.search(title: text)
                    guard !Task.isCancelled, revision == searchRevision else { return }
                    self.results = results
                case .director:
                    let people = try await personCatalog?.searchPeople(name: text) ?? []
                    guard !Task.isCancelled, revision == searchRevision else { return }
                    personResults = people
                }
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

    /// 只清空左侧搜索结果；右侧已经打开的草稿保留。
    func switchMode(to mode: SearchMode) {
        guard mode != searchMode, mode == .title || canSearchByDirector else { return }
        searchRevision += 1
        searchTask?.cancel()
        isSearching = false
        searchError = nil
        results = []
        personResults = []
        backToPeople()
        hasSearched = false
        searchMode = mode
    }

    @discardableResult
    func selectPerson(_ person: PersonSearchResult) -> Task<Void, Never> {
        backToPeople()
        guard let personCatalog else { return Task {} }
        selectedPerson = person
        isLoadingWorks = true
        let revision = worksRevision
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let works = try await personCatalog.directedWorks(personID: person.id)
                guard !Task.isCancelled, revision == worksRevision else { return }
                // 列出作品时读一次已保存的记录，用于标记「已添加」。
                savedWorkKeys = Set((try? store.recordsNewestFirst())?.map(\.mediaKey) ?? [])
                personWorks = works
                isLoadingWorks = false
            } catch {
                guard !Task.isCancelled, revision == worksRevision else { return }
                isLoadingWorks = false
                if !(error is CancellationError) { worksError = error.localizedDescription }
            }
        }
        worksTask = task
        return task
    }

    func backToPeople() {
        worksRevision += 1
        worksTask?.cancel()
        selectedPerson = nil
        personWorks = []
        worksError = nil
        isLoadingWorks = false
    }

    func isSaved(_ work: CreditedWork) -> Bool {
        savedWorkKeys.contains(work.id)
    }

    @discardableResult
    func select(_ candidate: MediaSearchResult) -> Task<Void, Never> {
        selectionRevision += 1
        detailsTask?.cancel()
        supplementalTask?.cancel()
        posterTask?.cancel()
        isLoadingPoster = false
        posterMessage = nil
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
                loadPoster(path: details.posterPath, revision: revision)
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
        guard savedRecordID == nil, !isSaving, !isLoadingPoster, let draft else { return nil }
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
        worksRevision += 1
        worksTask?.cancel()
        isLoadingWorks = false
        searchTask?.cancel()
        detailsTask?.cancel()
        supplementalTask?.cancel()
        isSearching = false
        isLoadingDetails = false
        isLoadingSupplemental = false
        posterTask?.cancel()
        isLoadingPoster = false
        posterMessage = nil
    }

    func retryPoster() {
        guard let draft, !isLoadingPoster, !isSaving else { return }
        loadPoster(path: draft.details.posterPath, revision: selectionRevision)
    }

    private func loadPoster(path: String?, revision: Int) {
        posterMessage = nil
        guard path != nil else { return }
        isLoadingPoster = true
        posterTask = Task { [weak self] in
            guard let self else { return }
            do {
                let poster = try await posters.load(path: path, filename: nil)
                guard !Task.isCancelled, revision == selectionRevision, !isSaving, draft != nil else { return }
                draft?.posterFilename = poster.filename
            } catch {
                guard !Task.isCancelled, revision == selectionRevision else { return }
                if !(error is CancellationError) {
                    posterMessage = "海报未能缓存：\(error.localizedDescription) 仍可保存，之后可在资料库重试。"
                }
            }
            guard revision == selectionRevision else { return }
            isLoadingPoster = false
        }
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
