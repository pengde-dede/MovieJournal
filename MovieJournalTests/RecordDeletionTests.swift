import Foundation
import SwiftData
import Testing
@testable import MovieJournal

@Suite("确认删除与海报清理")
@MainActor
struct RecordDeletionTests {
    @Test("请求删除和取消都不写库，只有确认按钮能够删除")
    func cancellationKeepsRecord() async throws {
        let fixture = try database()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let record = ViewingRecord(tmdbID: 278, mediaType: .movie, title: "保留的记录", myRating: 9)
        try fixture.store.insert(record)
        let cache = DeletionCache()
        let cleanup = PosterCleanupCoordinator(cache: cache)
        let model = RecordDetailViewModel()
        #expect(!model.confirmDeletion(store: fixture.store, cleanup: cleanup))
        model.requestDeletion(id: record.id, title: record.title)
        #expect(model.isShowingDeleteConfirmation && model.deletionRequest?.title == "保留的记录")
        #expect(try fixture.store.recordsNewestFirst().count == 1)
        model.cancelDeletion()
        #expect(!model.isShowingDeleteConfirmation && model.deletionRequest == nil)
        #expect(!model.confirmDeletion(store: fixture.store, cleanup: cleanup))
        #expect(cleanup.cleanupTask == nil)
        #expect(await cache.references.isEmpty)
        let reopened = try PersistenceController.makeContainer(in: fixture.directory)
        #expect(try RecordStore(context: reopened.mainContext).recordsNewestFirst().first?.title == "保留的记录")
    }

    @Test("确认删除后重开不再存在，仍有记录共用的海报保留")
    func deletionPersistsAndKeepsSharedPosters() async throws {
        let fixture = try database()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let directory = fixture.directory.appendingPathComponent("Posters", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let shared = try #require(PosterCache.filename(for: "/shared.jpg"))
        let independent = try #require(PosterCache.filename(for: "/independent.jpg"))
        for name in [shared, independent] { try PosterFixtures.png.write(to: directory.appendingPathComponent(name)) }
        let a = ViewingRecord(tmdbID: 1, mediaType: .movie, title: "电影", posterPath: "/shared.jpg", posterFilename: shared, myRating: 8)
        let b = ViewingRecord(tmdbID: 2, mediaType: .tv, title: "剧集", posterPath: "/shared.jpg", posterFilename: shared, myRating: 9, watchedSeason: 2)
        let c = ViewingRecord(tmdbID: 3, mediaType: .movie, title: "其他电影", posterPath: "/independent.jpg", posterFilename: independent, myRating: 7)
        for record in [a, b, c] { try fixture.store.insert(record) }
        let cache = PosterCache(directory: directory, transport: PosterTransport([]))
        let cleanup = PosterCleanupCoordinator(cache: cache)
        let model = RecordDetailViewModel()
        model.requestDeletion(id: a.id, title: a.title)
        #expect(model.confirmDeletion(store: fixture.store, cleanup: cleanup))
        await cleanup.cleanupTask?.value
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent(shared).path))
        model.requestDeletion(id: b.id, title: b.title)
        #expect(model.confirmDeletion(store: fixture.store, cleanup: cleanup))
        await cleanup.cleanupTask?.value
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(shared).path))
        #expect(try await cache.readData(filename: independent) == PosterFixtures.png)
        let reopened = try PersistenceController.makeContainer(in: fixture.directory)
        #expect(try RecordStore(context: reopened.mainContext).recordsNewestFirst().map(\.tmdbID) == [3])
        #expect(cleanup.cleanupMessage == nil && !cleanup.isCleaning)
    }

    @Test("删除保存失败时回滚，且不执行海报清理")
    func failedDeletionKeepsRecordAndPosters() async throws {
        let fixture = try database()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let record = ViewingRecord(tmdbID: 278, mediaType: .movie, title: "删除失败应保留", myRating: 9, shortReview: "保留短评")
        let id = record.id
        try fixture.store.insert(record)
        let failingStore = RecordStore(context: fixture.container.mainContext) { throw DeleteFailure.unavailable }
        let cache = DeletionCache()
        let cleanup = PosterCleanupCoordinator(cache: cache)
        let model = RecordDetailViewModel()
        model.requestDeletion(id: id, title: record.title)
        #expect(!model.confirmDeletion(store: failingStore, cleanup: cleanup))
        #expect(model.deleteError != nil && !model.isShowingDeleteConfirmation)
        #expect(!fixture.container.mainContext.hasChanges)
        #expect(record.title == "删除失败应保留" && record.myRating == 9 && record.shortReview == "保留短评")
        #expect(try fixture.store.recordsNewestFirst().first?.shortReview == "保留短评")
        #expect(cleanup.cleanupTask == nil && !cleanup.isCleanupPending)
        #expect(await cache.references.isEmpty)
        let reopened = try PersistenceController.makeContainer(in: fixture.directory)
        #expect(try RecordStore(context: reopened.mainContext).recordsNewestFirst().first?.id == id)
        model.requestDeletion(id: id, title: "删除失败应保留")
        #expect(model.confirmDeletion(store: fixture.store, cleanup: cleanup))
        await cleanup.cleanupTask?.value
        #expect(try fixture.store.recordsNewestFirst().isEmpty)
        #expect(await cache.references.count == 1)
    }

    @Test("另一窗口先删除时，旧确认不崩溃也不重复执行清理")
    func staleConfirmationDoesNotDeleteAnotherRecord() async throws {
        let fixture = try database()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let record = ViewingRecord(tmdbID: 278, mediaType: .movie, title: "同一作品", myRating: 9)
        let id = record.id
        try fixture.store.insert(record)
        let model = RecordDetailViewModel()
        model.requestDeletion(id: id, title: record.title)
        try fixture.store.delete(recordID: id)
        let replacement = ViewingRecord(tmdbID: 278, mediaType: .movie, title: "重新添加的记录", myRating: 8)
        try fixture.store.insert(replacement)
        let cache = DeletionCache()
        let cleanup = PosterCleanupCoordinator(cache: cache)
        #expect(!model.confirmDeletion(store: fixture.store, cleanup: cleanup))
        #expect(model.deleteError?.contains("其他窗口删除") == true)
        #expect(try fixture.store.recordsNewestFirst().map(\.id) == [replacement.id])
        #expect(await cache.references.isEmpty)
    }

    @Test("文件清理失败不撤销删除，重试仍以当前记录的引用为准")
    func cleanupFailureCanRetry() async throws {
        let fixture = try database()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let record = ViewingRecord(tmdbID: 278, mediaType: .movie, title: "删除", myRating: 9)
        try fixture.store.insert(record)
        let cache = DeletionCache(failFirst: true)
        let cleanup = PosterCleanupCoordinator(cache: cache)
        let model = RecordDetailViewModel()
        model.requestDeletion(id: record.id, title: record.title)
        #expect(model.confirmDeletion(store: fixture.store, cleanup: cleanup))
        await cleanup.cleanupTask?.value
        #expect(cleanup.cleanupMessage != nil && !cleanup.isCleaning)
        #expect(try fixture.store.recordsNewestFirst().isEmpty)
        cleanup.requestCleanup(store: fixture.store)
        await cleanup.cleanupTask?.value
        #expect(cleanup.cleanupMessage == nil && !cleanup.isCleanupPending)
        #expect(await cache.references == [[], []])
    }

    private func database() throws -> (directory: URL, container: ModelContainer, store: RecordStore) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MovieJournalDeletionTests-\(UUID().uuidString)", isDirectory: true)
        let container = try PersistenceController.makeContainer(in: directory)
        return (directory, container, RecordStore(context: container.mainContext))
    }
}

private enum DeleteFailure: Error { case unavailable }

private actor DeletionCache: PosterFileManaging {
    private var failFirst: Bool
    private(set) var references: [Set<String>] = []
    init(failFirst: Bool = false) { self.failFirst = failFirst }
    func existingFilename(path: String?, filename: String?) -> String? { filename }
    func readData(filename: String) throws -> Data { PosterFixtures.png }
    func load(path: String?, filename: String?) throws -> CachedPoster { throw PosterCacheError.noPoster }
    func cleanupAtStartup(referencedFilenames: Set<String>) throws -> Int { 0 }
    func removeUnreferencedFiles(referencedFilenames: Set<String>) throws -> Int {
        references.append(referencedFilenames)
        if failFirst { failFirst = false; throw PosterCacheError.cleanupFailed }
        return 0
    }
}
