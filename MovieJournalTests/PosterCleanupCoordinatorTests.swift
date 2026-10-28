import Foundation
import SwiftData
import Testing
@testable import MovieJournal

@Suite("多窗口草稿海报保护")
@MainActor
struct PosterCleanupCoordinatorTests {
    @Test("删除后等所有添加窗口关闭，再保留刚保存的草稿或清理已取消的草稿", arguments: [true, false])
    func twoDraftWindowsDelayCleanup(saveLastDraft: Bool) async throws {
        let fixture = try database()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let directory = fixture.directory.appendingPathComponent("Posters", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let oldName = try #require(PosterCache.filename(for: "/old.jpg"))
        try PosterFixtures.png.write(to: directory.appendingPathComponent(oldName))
        let old = ViewingRecord(tmdbID: 99, mediaType: .movie, title: "待删除", posterPath: "/old.jpg", posterFilename: oldName, myRating: 8)
        try fixture.store.insert(old)
        let transport = PosterTransport(Array(repeating: .success(HTTPResponse(data: PosterFixtures.png, statusCode: 200)), count: 2))
        let cache = PosterCache(directory: directory, transport: transport)
        let cleanup = PosterCleanupCoordinator(cache: cache)
        // 与两个主窗口各自打开添加表单相同，先登记，再允许表单发起下载。
        let firstSession = try #require(cleanup.beginAdding())
        let lastSession = try #require(cleanup.beginAdding())
        let first = AddRecordViewModel(catalog: CleanupCatalog(), store: fixture.store, posters: cache)
        let last = AddRecordViewModel(catalog: CleanupCatalog(), store: fixture.store, posters: cache)
        await first.select(Fixtures.movie).value
        await first.posterTask?.value
        await first.supplementalTask?.value
        await last.select(Fixtures.series).value
        await last.posterTask?.value
        await last.supplementalTask?.value
        let firstName = try #require(first.draft?.posterFilename)
        let lastName = try #require(last.draft?.posterFilename)
        let allNames: Set<String> = [oldName, firstName, lastName]
        let detail = RecordDetailViewModel()
        detail.requestDeletion(id: old.id, title: old.title)
        #expect(detail.confirmDeletion(store: fixture.store, cleanup: cleanup))
        #expect(cleanup.isCleanupPending && cleanup.cleanupTask == nil && !cleanup.isCleaning)
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: directory.path)) == allNames)
        first.cancelPendingWork()
        cleanup.finishAdding(firstSession, store: fixture.store)
        // 某个窗口消失的通知可能重复，不能误把另一个窗口的保护一并解除。
        cleanup.finishAdding(firstSession, store: fixture.store)
        #expect(cleanup.cleanupTask == nil && cleanup.isCleanupPending)
        #expect(try await cache.readData(filename: lastName) == PosterFixtures.png)
        if saveLastDraft {
            last.draft?.myRating = 9
            last.draft?.watchedSeason = 3
            #expect(last.saveRecord() != nil)
        }
        last.cancelPendingWork()
        cleanup.finishAdding(lastSession, store: fixture.store)
        await cleanup.cleanupTask?.value
        let expected: Set<String> = saveLastDraft ? [lastName] : []
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: directory.path)) == expected)
        #expect(!cleanup.isCleanupPending && !cleanup.isCleaning && cleanup.cleanupMessage == nil)
        let reopened = try PersistenceController.makeContainer(in: fixture.directory)
        let records = try RecordStore(context: reopened.mainContext).recordsNewestFirst()
        #expect(records.count == (saveLastDraft ? 1 : 0))
        if saveLastDraft {
            let record = try #require(records.first)
            #expect(record.posterFilename == lastName && record.watchedSeason == 3)
            let offline = PosterTransport([])
            let reopenedCache = PosterCache(directory: directory, transport: offline)
            #expect(try await reopenedCache.readData(filename: lastName) == PosterFixtures.png)
            #expect(await offline.requests.isEmpty)
        }
    }

    @Test("缺失海报刚补存但引用尚未回写时，删除清理仍保留剩余记录的文件")
    func backfillAwaitingReferenceIsRetained() async throws {
        let fixture = try database()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let path = "/backfill-pending.jpg"
        let record = ViewingRecord(tmdbID: 1, mediaType: .movie, title: "正在补存海报", posterPath: path, myRating: 8)
        try fixture.store.insert(record)
        let directory = fixture.directory.appendingPathComponent("Posters", isDirectory: true)
        let transport = PosterTransport([.success(HTTPResponse(data: PosterFixtures.png, statusCode: 200))])
        let cache = PosterCache(directory: directory, transport: transport)
        // 复现下载返回后、LibraryViewModel 回写引用前的间隙，此时已经不在 inFlight 中。
        let downloaded = try await cache.load(path: path, filename: nil)
        #expect(record.posterFilename == nil && downloaded.wasWritten)
        let cleanup = PosterCleanupCoordinator(cache: cache)
        cleanup.requestCleanup(store: fixture.store)
        await cleanup.cleanupTask?.value
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent(downloaded.filename).path))
        try fixture.store.setPosterFilename(downloaded.filename, recordID: record.id, expectedPath: path)
        #expect(await transport.requests.count == 1)
    }

    @Test("清理进行中阻止新添加，期间的再次删除以最新引用补做")
    func cleaningGateAndConcurrentDeletion() async throws {
        let fixture = try database()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let record = ViewingRecord(tmdbID: 1, mediaType: .movie, title: "剩余记录", posterFilename: "retained.image", myRating: 9)
        let id = record.id
        try fixture.store.insert(record)
        let cache = GatedDeletionCache()
        let cleanup = PosterCleanupCoordinator(cache: cache)
        cleanup.requestCleanup(store: fixture.store)
        #expect(cleanup.isCleaning && cleanup.beginAdding() == nil)
        await cache.waitForCleanup()
        try fixture.store.delete(recordID: id)
        cleanup.requestCleanup(store: fixture.store)
        #expect(cleanup.isCleanupPending && cleanup.beginAdding() == nil)
        await cache.finishCleanup()
        await cleanup.cleanupTask?.value
        #expect(await cache.references == [["retained.image"], []])
        #expect(!cleanup.isCleaning && !cleanup.isCleanupPending)
        let session = try #require(cleanup.beginAdding())
        cleanup.finishAdding(session, store: fixture.store)
    }

    @Test("另一窗口打开时启动清理也延后，多窗口共用同一次启动清理")
    func startupDefersSafelyAndRunsOnce() async throws {
        let fixture = try database()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let directory = fixture.directory.appendingPathComponent("Posters", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let orphan = try #require(PosterCache.filename(for: "/draft.jpg"))
        try PosterFixtures.png.write(to: directory.appendingPathComponent(orphan))
        let cache = PosterCache(directory: directory, transport: PosterTransport([]))
        let cleanup = PosterCleanupCoordinator(cache: cache)
        let session = try #require(cleanup.beginAdding())
        let firstLibrary = LibraryViewModel()
        let secondLibrary = LibraryViewModel()
        await firstLibrary.cacheSavedPosters([], cache: cache, store: fixture.store, cleanup: cleanup)
        await secondLibrary.cacheSavedPosters([], cache: cache, store: fixture.store, cleanup: cleanup)
        #expect(cleanup.cleanupTask == nil && cleanup.isCleanupPending)
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent(orphan).path))
        cleanup.finishAdding(session, store: fixture.store)
        await cleanup.cleanupTask?.value
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(orphan).path))
        try PosterFixtures.png.write(to: directory.appendingPathComponent(orphan))
        await cleanup.cleanupAtStartup(store: fixture.store)
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent(orphan).path))
        cleanup.requestCleanup(store: fixture.store)
        await cleanup.cleanupTask?.value
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(orphan).path))
    }

    private func database() throws -> (directory: URL, container: ModelContainer, store: RecordStore) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MovieJournalCleanupTests-\(UUID().uuidString)", isDirectory: true)
        let container = try PersistenceController.makeContainer(in: directory)
        return (directory, container, RecordStore(context: container.mainContext))
    }
}

private nonisolated struct CleanupCatalog: MediaCatalogServing {
    func search(title: String) async throws -> [MediaSearchResult] { [Fixtures.movie, Fixtures.series] }
    func details(for candidate: MediaSearchResult) async throws -> MediaDetails { Fixtures.details(candidate) }
    func supplementalRatings(imdbID: String?) async throws -> SupplementalRatingsResult { .notConfigured }
}

private actor GatedDeletionCache: PosterFileManaging {
    private(set) var references: [Set<String>] = []
    private var continuation: CheckedContinuation<Void, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    func existingFilename(path: String?, filename: String?) -> String? { filename }
    func readData(filename: String) throws -> Data { PosterFixtures.png }
    func load(path: String?, filename: String?) throws -> CachedPoster { throw PosterCacheError.noPoster }
    func cleanupAtStartup(referencedFilenames: Set<String>) throws -> Int { 0 }
    func removeUnreferencedFiles(referencedFilenames: Set<String>) async throws -> Int {
        references.append(referencedFilenames)
        if references.count == 1 {
            await withCheckedContinuation { continuation = $0; waiter?.resume(); waiter = nil }
        }
        return 0
    }
    func waitForCleanup() async {
        if continuation != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func finishCleanup() { continuation?.resume(); continuation = nil }
}
