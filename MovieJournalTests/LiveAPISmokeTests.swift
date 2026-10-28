import AppKit
import Foundation
import SwiftData
import Testing
@testable import MovieJournal

// 默认不联网；显式启用后，凭据只在应用测试进程中读取并用于官方 HTTPS 接口。
@Suite("可选真实 TMDB 与完整本地流程验收", .enabled(if: ProcessInfo.processInfo.environment["MOVIEJOURNAL_LIVE_API_TESTS"] == "1" || ProcessInfo.processInfo.environment["TEST_RUNNER_MOVIEJOURNAL_LIVE_API_TESTS"] == "1"))
@MainActor
struct LiveAPISmokeTests {
    @Test("两部指定作品的真实搜索、资料、离线重开、编辑与删除", .timeLimit(.minutes(2)))
    func tmdbSearchDetailsAndPersistence() async throws {
        let keychain = KeychainService()
        guard let key = try await keychain.read(.tmdb).nonEmpty else { throw APIError.missingKey(.tmdb) }
        let transport = HTTPClient()
        let client = TMDBClient(transport: transport)
        try await client.authenticate(key: key)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MovieJournalLiveTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let posterDirectory = directory.appendingPathComponent("Posters", isDirectory: true)
        let posterCache = PosterCache(directory: posterDirectory, transport: transport)
        let thumbnails = PosterThumbnailCache(transport: transport)
        let cases: [(String, MediaType, Int)] = [("肖申克的救赎", .movie, 278), ("绝命毒师", .tv, 1396)]
        for (title, type, identifier) in cases {
            let results = try await client.search(title: title, key: key)
            let candidate = try #require(results.first { $0.tmdbID == identifier && $0.mediaType == type })
            let before = (try? FileManager.default.contentsOfDirectory(atPath: posterDirectory.path)) ?? []
            let thumbnail = try await thumbnails.load(path: candidate.posterPath)
            #expect(NSImage(data: thumbnail) != nil)
            let after = (try? FileManager.default.contentsOfDirectory(atPath: posterDirectory.path)) ?? []
            #expect(Set(before) == Set(after))
            let details = try await client.details(for: candidate, key: key)
            #expect(!details.title.isEmpty)
            #expect(!details.originalTitle.isEmpty)
            #expect(!details.creatorNames.isEmpty)
            #expect(details.castNames.count == 5)
            #expect(details.tmdbRating != nil)
            #expect(!details.overview.isEmpty)
            let poster = try await posterCache.load(path: details.posterPath, filename: nil)
            #expect(NSImage(data: poster.data) != nil)
            try saveTemporaryRecord(details, posterFilename: poster.filename, in: directory)
        }
        let reopened = try PersistenceController.makeContainer(in: directory)
        let store = RecordStore(context: reopened.mainContext)
        let records = try store.recordsNewestFirst()
        #expect(records.count == 2)
        #expect(Set(records.map(\.mediaKey)) == ["movie:278", "tv:1396"])
        #expect(records.allSatisfy { !$0.creatorNames.isEmpty && $0.castNames.count == 5 && $0.tmdbRating != nil })
        let referenced = Set(records.compactMap(\.posterFilename))
        #expect(try await posterCache.cleanupAtStartup(referencedFilenames: referenced) == 0)
        let offline = PosterTransport([])
        let reopenedPosters = PosterCache(directory: posterDirectory, transport: offline)
        for record in records {
            let filename = try #require(record.posterFilename)
            let local = try await reopenedPosters.load(path: record.posterPath, filename: filename)
            #expect(NSImage(data: local.data) != nil)
        }
        #expect(await offline.requests.isEmpty)
        // 编辑和删除只处理前面真实下载的临时记录；正式资料库不受影响。
        let series = try #require(records.first { $0.mediaType == .tv })
        let edit = EditRecordViewModel(record: series, store: store)
        edit.draft.myRating = 9
        edit.draft.watchedSeasonText = "2"
        edit.draft.shortReview = "离线编辑验收"
        #expect(edit.save())
        let movie = try #require(records.first { $0.mediaType == .movie })
        let movieFilename = try #require(movie.posterFilename)
        let cleanup = PosterCleanupCoordinator(cache: reopenedPosters)
        let deletion = RecordDetailViewModel()
        deletion.requestDeletion(id: movie.id, title: movie.title)
        #expect(deletion.confirmDeletion(store: store, cleanup: cleanup))
        await cleanup.cleanupTask?.value
        #expect(!FileManager.default.fileExists(atPath: posterDirectory.appendingPathComponent(movieFilename).path))
        let finalContainer = try PersistenceController.makeContainer(in: directory)
        let finalRecords = try RecordStore(context: finalContainer.mainContext).recordsNewestFirst()
        #expect(finalRecords.count == 1)
        let finalSeries = try #require(finalRecords.first)
        #expect(finalSeries.mediaKey == "tv:1396" && finalSeries.myRating == 9)
        #expect(finalSeries.watchedSeason == 2 && finalSeries.shortReview == "离线编辑验收")
        let finalFilename = try #require(finalSeries.posterFilename)
        let finalPoster = try await reopenedPosters.readData(filename: finalFilename)
        #expect(NSImage(data: finalPoster) != nil)
        #expect(await offline.requests.isEmpty)
    }

    private func saveTemporaryRecord(_ details: MediaDetails, posterFilename: String, in directory: URL) throws {
        let container = try PersistenceController.makeContainer(in: directory)
        var draft = RecordDraft(details: details)
        draft.posterFilename = posterFilename
        draft.myRating = 8
        draft.shortReview = "自动化验收，仅存临时数据库"
        if details.mediaType == .tv { draft.watchedSeason = 1 }
        try RecordStore(context: container.mainContext).insert(draft.makeRecord())
    }
}
