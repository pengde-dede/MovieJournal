import Foundation
import SwiftData
import Testing
@testable import MovieJournal

@Suite("本地资料库与离线海报")
@MainActor
struct LibraryTests {
    @Test("片名搜索同时匹配中文名、原名，忽略大小写及首尾空白")
    func localTitleSearchAndTypeFilter() throws {
        let records = sampleRecords()
        let model = LibraryViewModel()
        #expect(model.matchingRecords(in: records).map(\.tmdbID) == [1396, 346, 278])
        model.searchText = "  七武  "
        #expect(model.matchingRecords(in: records).map(\.tmdbID) == [346])
        model.searchText = " breaking BAD "
        #expect(model.matchingRecords(in: records).map(\.tmdbID) == [1396])
        model.mediaFilter = .movie
        #expect(model.matchingRecords(in: records).isEmpty)
        model.searchText = ""
        #expect(model.matchingRecords(in: records).map(\.tmdbID) == [346, 278])
        model.mediaFilter = .tv
        #expect(model.matchingRecords(in: records).map(\.tmdbID) == [1396])
        model.resetFilters()
        #expect(model.matchingRecords(in: records).count == 3)
        model.searchText = "搜不到的作品"
        #expect(model.matchingRecords(in: records).isEmpty)
    }

    @Test("搜索和筛选保留数据库按添加时间倒序的结果")
    func filteringPreservesAddedOrder() throws {
        let fixture = try databaseFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let samples = sampleRecords()
        for record in samples.reversed() { try fixture.store.insert(record) }
        let newest = try fixture.store.recordsNewestFirst()
        let model = LibraryViewModel()
        model.mediaFilter = .movie
        #expect(model.matchingRecords(in: newest).map(\.tmdbID) == [346, 278])
        #expect(model.matchingRecords(in: []).isEmpty)
    }

    @Test("已有记录补存海报后，数据库与图片重开都无需网络")
    func backfillAndReopenOffline() async throws {
        let fixture = try databaseFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let record = ViewingRecord(tmdbID: 278, mediaType: .movie, title: "肖申克的救赎", posterPath: "/legacy.jpg", myRating: 9, shortReview: "保留个人短评")
        let createdAt = record.createdAt
        let updatedAt = record.updatedAt
        try fixture.store.insert(record)
        let imageDirectory = fixture.directory.appendingPathComponent("Posters", isDirectory: true)
        let online = PosterTransport([.success(HTTPResponse(data: PosterFixtures.png, statusCode: 200))])
        let cache = PosterCache(directory: imageDirectory, transport: online)
        let cleanup = PosterCleanupCoordinator(cache: cache)
        let model = LibraryViewModel()
        await model.cacheSavedPosters([SavedPosterTarget(recordID: record.id, path: record.posterPath, filename: nil)],
            cache: cache, store: fixture.store, cleanup: cleanup)
        #expect(model.posterMessage == nil)
        let reopened = try PersistenceController.makeContainer(in: fixture.directory)
        let saved = try #require(RecordStore(context: reopened.mainContext).recordsNewestFirst().first)
        let filename = try #require(saved.posterFilename)
        #expect(saved.myRating == 9 && saved.shortReview == "保留个人短评")
        #expect(saved.createdAt == createdAt && saved.updatedAt == updatedAt)
        let offline = PosterTransport([])
        let poster = try await PosterCache(directory: imageDirectory, transport: offline).load(path: saved.posterPath, filename: filename)
        #expect(poster.data == PosterFixtures.png)
        #expect(await offline.requests.isEmpty)
    }

    @Test("补存失败仍保留全部资料，恢复联网后可重试并清除提示")
    func failedBackfillCanRetry() async throws {
        let fixture = try databaseFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let record = ViewingRecord(tmdbID: 1396, mediaType: .tv, title: "绝命毒师", posterPath: "/series.jpg", myRating: 8, watchedSeason: 2)
        try fixture.store.insert(record)
        let transport = PosterTransport([.failure(.networkUnavailable), .success(HTTPResponse(data: PosterFixtures.png, statusCode: 200))])
        let cache = PosterCache(directory: fixture.directory.appendingPathComponent("Posters"), transport: transport)
        let target = SavedPosterTarget(recordID: record.id, path: record.posterPath, filename: nil)
        let cleanup = PosterCleanupCoordinator(cache: cache)
        let model = LibraryViewModel()
        await model.cacheSavedPosters([target], cache: cache, store: fixture.store, cleanup: cleanup)
        #expect(model.posterMessage != nil)
        #expect(record.posterFilename == nil)
        #expect(model.posterReloadVersions.isEmpty)
        #expect(model.matchingRecords(in: try fixture.store.recordsNewestFirst()).count == 1)
        let previousReload = model.posterReloadVersions
        await model.cacheSavedPosters([target], cache: cache, store: fixture.store, cleanup: cleanup)
        #expect(model.posterMessage == nil)
        #expect(record.posterFilename != nil)
        #expect(model.posterReloadVersions != previousReload)
        #expect(record.myRating == 8 && record.watchedSeason == 2)
    }

    @Test("资料已改变或记录不存在时，旧海报结果不写回记录")
    func outdatedPosterReferenceIsIgnored() throws {
        let fixture = try databaseFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let record = ViewingRecord(tmdbID: 278, mediaType: .movie, title: "电影", posterPath: "/new.jpg", myRating: 8)
        try fixture.store.insert(record)
        try fixture.store.setPosterFilename("obsolete.image", recordID: record.id, expectedPath: "/old.jpg")
        try fixture.store.setPosterFilename("missing.image", recordID: UUID(), expectedPath: nil)
        #expect(record.posterFilename == nil)
    }

    private func sampleRecords() -> [ViewingRecord] {
        [ViewingRecord(tmdbID: 1396, mediaType: .tv, title: "绝命毒师", originalTitle: "Breaking Bad", myRating: 9, createdAt: Date(timeIntervalSince1970: 300)),
         ViewingRecord(tmdbID: 346, mediaType: .movie, title: "七武士", originalTitle: "Seven Samurai", myRating: 9, createdAt: Date(timeIntervalSince1970: 200)),
         ViewingRecord(tmdbID: 278, mediaType: .movie, title: "肖申克的救赎", originalTitle: "The Shawshank Redemption", myRating: 10, createdAt: Date(timeIntervalSince1970: 100))]
    }

    private func databaseFixture() throws -> (directory: URL, container: ModelContainer, store: RecordStore) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MovieJournalLibraryTests-\(UUID().uuidString)", isDirectory: true)
        let container = try PersistenceController.makeContainer(in: directory)
        return (directory, container, RecordStore(context: container.mainContext))
    }
}
