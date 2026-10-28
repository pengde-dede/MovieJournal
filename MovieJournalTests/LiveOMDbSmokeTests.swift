import Foundation
import SwiftData
import Testing
@testable import MovieJournal

// 独立开关；普通测试和仅启用 TMDB 验收时不访问真实 OMDb Key。
@Suite("可选真实 OMDb 旧记录补分验收", .enabled(if: ProcessInfo.processInfo.environment["MOVIEJOURNAL_LIVE_OMDB_TESTS"] == "1" || ProcessInfo.processInfo.environment["TEST_RUNNER_MOVIEJOURNAL_LIVE_OMDB_TESTS"] == "1"))
@MainActor
struct LiveOMDbSmokeTests {
    @Test("两部指定作品从缺失评分补取并保存，重开仍可读", .timeLimit(.minutes(2)), arguments: [MediaType.movie, .tv])
    func refreshExistingRecord(type: MediaType) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MovieJournalLiveOMDbTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try PersistenceController.makeContainer(in: directory)
        let store = RecordStore(context: container.mainContext)
        let details = Fixtures.details(type == .movie ? Fixtures.movie : Fixtures.series)
        let record = ViewingRecord(tmdbID: details.tmdbID, mediaType: type, title: details.title,
            imdbID: details.imdbID, myRating: 8, shortReview: "仅存临时数据库", watchedSeason: type == .tv ? 2 : nil)
        let identifier = record.id
        let createdAt = record.createdAt
        try store.insert(record)
        let model = RecordDetailViewModel()
        let catalog = MediaCatalogService(keychain: KeychainService())
        await model.refreshRatings(recordID: identifier, imdbID: record.imdbID, catalog: catalog, store: store).value
        #expect(!model.ratingsRefreshFailed)
        let imdb = try #require(record.imdbRating)
        #expect((0...10).contains(imdb))
        // OMDb 不保证每部作品都有烂番茄评分，缺失时应保持为空。
        if let tomatoes = record.rottenTomatoesRating { #expect((0...100).contains(tomatoes)) }
        let tomatoes = record.rottenTomatoesRating
        let reopened = try PersistenceController.makeContainer(in: directory)
        let records = try RecordStore(context: reopened.mainContext).recordsNewestFirst()
        #expect(records.count == 1)
        let saved = try #require(records.first)
        #expect(saved.id == identifier && saved.createdAt == createdAt)
        #expect(saved.imdbRating == imdb && saved.rottenTomatoesRating == tomatoes)
        #expect(saved.myRating == 8 && saved.shortReview == "仅存临时数据库")
    }
}
