import AppKit
import Foundation
import SwiftData
import Testing
@testable import MovieJournal

// 默认不联网；显式启用后，凭据只在应用测试进程中读取并用于官方 HTTPS 接口。
@Suite("可选真实 TMDB 验收", .enabled(if: ProcessInfo.processInfo.environment["MOVIEJOURNAL_LIVE_API_TESTS"] == "1" || ProcessInfo.processInfo.environment["TEST_RUNNER_MOVIEJOURNAL_LIVE_API_TESTS"] == "1"))
@MainActor
struct LiveAPISmokeTests {
    @Test("两部指定作品的真实搜索、资料、海报及本地重开", .timeLimit(.minutes(2)))
    func tmdbSearchDetailsAndPersistence() async throws {
        let keychain = KeychainService()
        guard let key = try await keychain.read(.tmdb).nonEmpty else { throw APIError.missingKey(.tmdb) }
        let transport = HTTPClient()
        let client = TMDBClient(transport: transport)
        try await client.authenticate(key: key)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MovieJournalLiveTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let cases: [(String, MediaType, Int)] = [("肖申克的救赎", .movie, 278), ("绝命毒师", .tv, 1396)]
        for (title, type, identifier) in cases {
            let results = try await client.search(title: title, key: key)
            let candidate = try #require(results.first { $0.tmdbID == identifier && $0.mediaType == type })
            let details = try await client.details(for: candidate, key: key)
            #expect(!details.title.isEmpty)
            #expect(!details.originalTitle.isEmpty)
            #expect(!details.creatorNames.isEmpty)
            #expect(details.castNames.count == 5)
            #expect(details.tmdbRating != nil)
            #expect(!details.overview.isEmpty)
            let posterURL = try #require(TMDBImageURL.poster(details.posterPath))
            let poster = try await transport.send(URLRequest(url: posterURL))
            #expect(poster.statusCode == 200)
            #expect(NSImage(data: poster.data) != nil)
            try saveTemporaryRecord(details, in: directory)
        }
        let reopened = try PersistenceController.makeContainer(in: directory)
        let records = try RecordStore(context: reopened.mainContext).recordsNewestFirst()
        #expect(records.count == 2)
        #expect(Set(records.map(\.mediaKey)) == ["movie:278", "tv:1396"])
        #expect(records.allSatisfy { !$0.creatorNames.isEmpty && $0.castNames.count == 5 && $0.tmdbRating != nil })
    }

    private func saveTemporaryRecord(_ details: MediaDetails, in directory: URL) throws {
        let container = try PersistenceController.makeContainer(in: directory)
        var draft = RecordDraft(details: details)
        draft.myRating = 8
        draft.shortReview = "自动化验收，仅存临时数据库"
        if details.mediaType == .tv { draft.watchedSeason = 1 }
        try RecordStore(context: container.mainContext).insert(draft.makeRecord())
    }
}
