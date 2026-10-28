import Foundation
import SwiftData
import Testing
@testable import MovieJournal

@Suite("海报与保存流程")
@MainActor
struct PosterWorkflowTests {
    @Test("新记录先完成海报缓存，再把相对文件名写入资料库")
    func savingWaitsForPosterThenPersistsFilename() async throws {
        let fixture = try databaseFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let cache = ControlledPosterCache()
        let model = AddRecordViewModel(catalog: ImmediateCatalog(), store: fixture.store, posters: cache)
        await model.select(Fixtures.movie).value
        await cache.waitForMovie()
        model.draft?.myRating = 9
        #expect(model.isLoadingPoster)
        #expect(model.saveRecord() == nil)
        #expect(try fixture.store.recordsNewestFirst().isEmpty)
        await cache.finishMovie()
        await model.posterTask?.value
        #expect(!model.isLoadingPoster)
        #expect(model.saveRecord() != nil)
        let reopened = try PersistenceController.makeContainer(in: fixture.directory)
        let record = try #require(RecordStore(context: reopened.mainContext).recordsNewestFirst().first)
        #expect(record.posterFilename == PosterCache.filename(for: Fixtures.movie.posterPath))
        #expect(record.myRating == 9)
    }

    @Test("海报失败仍可保存文字与个人信息")
    func posterFailureDoesNotPreventSaving() async throws {
        let fixture = try databaseFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let model = AddRecordViewModel(catalog: ImmediateCatalog(), store: fixture.store, posters: StubPosterCache(failure: .downloadFailed))
        await model.select(Fixtures.movie).value
        await model.posterTask?.value
        model.draft?.myRating = 8
        model.draft?.shortReview = "图片失败也保留"
        #expect(model.posterMessage != nil)
        #expect(model.saveRecord() != nil)
        let record = try #require(fixture.store.recordsNewestFirst().first)
        #expect(record.posterFilename == nil)
        #expect(record.shortReview == "图片失败也保留")
    }

    @Test("上一个作品的海报晚返回，不覆盖新作品草稿")
    func latePosterCannotOverwriteNewSelection() async throws {
        let fixture = try databaseFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let cache = ControlledPosterCache()
        let model = AddRecordViewModel(catalog: ImmediateCatalog(), store: fixture.store, posters: cache)
        await model.select(Fixtures.movie).value
        let old = model.posterTask
        await cache.waitForMovie()
        await model.select(Fixtures.series).value
        await model.posterTask?.value
        await cache.finishMovie()
        await old?.value
        #expect(model.draft?.details.tmdbID == Fixtures.series.tmdbID)
        #expect(model.draft?.posterFilename == PosterCache.filename(for: Fixtures.series.posterPath))
        #expect(!model.isLoadingPoster)
    }

    @Test("取消的旧补存批次不修改新批次状态或数据库")
    func cancelledBackfillDoesNotWriteLateResults() async throws {
        let fixture = try databaseFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let record = ViewingRecord(tmdbID: 278, mediaType: .movie, title: "电影", posterPath: Fixtures.movie.posterPath, myRating: 8)
        try fixture.store.insert(record)
        let cache = ControlledPosterCache()
        let model = LibraryViewModel()
        let task = Task {
            await model.cacheSavedPosters([SavedPosterTarget(recordID: record.id, path: record.posterPath, filename: nil)], cache: cache, store: fixture.store)
        }
        await cache.waitForMovie()
        task.cancel()
        await model.cacheSavedPosters([], cache: cache, store: fixture.store)
        let currentReload = model.posterReloadToken
        await cache.finishMovie()
        await task.value
        #expect(record.posterFilename == nil)
        #expect(!model.isCachingPosters && model.totalPosters == 0 && model.completedPosters == 0)
        #expect(model.posterReloadToken == currentReload)
        #expect(model.posterMessage == nil)
    }

    private func databaseFixture() throws -> (directory: URL, container: ModelContainer, store: RecordStore) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MovieJournalPosterWorkflowTests-\(UUID().uuidString)", isDirectory: true)
        let container = try PersistenceController.makeContainer(in: directory)
        return (directory, container, RecordStore(context: container.mainContext))
    }
}

private nonisolated struct ImmediateCatalog: MediaCatalogServing {
    func search(title: String) async throws -> [MediaSearchResult] { [Fixtures.movie, Fixtures.series] }
    func details(for candidate: MediaSearchResult) async throws -> MediaDetails { Fixtures.details(candidate) }
    func supplementalRatings(imdbID: String?) async throws -> SupplementalRatingsResult { .notConfigured }
}

private actor ControlledPosterCache: PosterCaching {
    private var continuation: CheckedContinuation<CachedPoster, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    func load(path: String?, filename: String?) async throws -> CachedPoster {
        guard let name = PosterCache.filename(for: path) else { throw PosterCacheError.noPoster }
        if path != Fixtures.movie.posterPath { return CachedPoster(data: PosterFixtures.png, filename: name) }
        return await withCheckedContinuation {
            continuation = $0
            waiter?.resume(); waiter = nil
        }
    }
    func waitForMovie() async {
        if continuation != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func finishMovie() {
        guard let name = PosterCache.filename(for: Fixtures.movie.posterPath) else { return }
        continuation?.resume(returning: CachedPoster(data: PosterFixtures.png, filename: name))
        continuation = nil
    }
}
