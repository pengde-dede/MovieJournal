import Foundation
import SwiftData
import Testing
@testable import MovieJournal

@Suite("本地资料库")
@MainActor
struct PersistenceTests {
    @Test("电影资料写入磁盘后可重新打开并完整读取")
    func movieSurvivesReopeningStore() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID()
        let watchedOn = Date(timeIntervalSince1970: 1_793_030_400)
        let addedAt = Date(timeIntervalSince1970: 1_793_034_000)

        // 在独立作用域里写入，退出后重新创建容器，避免只验证同一上下文的内存。
        try writeMovie(in: directory, id: id, watchedOn: watchedOn, addedAt: addedAt)
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("MovieJournal.store").path))

        let reopened = try PersistenceController.makeContainer(in: directory)
        let configuration = try #require(reopened.configurations.first)
        #expect(!configuration.isStoredInMemoryOnly)
        #expect(configuration.cloudKitContainerIdentifier == nil)
        #expect(reopened.migrationPlan == MovieJournalMigrationPlan.self)
        let records = try RecordStore(context: reopened.mainContext).recordsNewestFirst()
        #expect(records.count == 1)
        let record = try #require(records.first)
        #expect(record.id == id)
        #expect(record.mediaKey == "movie:278")
        #expect(record.tmdbID == 278)
        #expect(record.mediaType == .movie)
        #expect(record.title == "肖申克的救赎")
        #expect(record.originalTitle == "The Shawshank Redemption")
        #expect(record.releaseYear == 1994)
        #expect(record.genres == ["剧情", "犯罪"])
        #expect(record.overview == "电影简介（测试资料）")
        #expect(record.overviewLanguage == "zh-CN")
        #expect(record.creatorNames == ["Frank Darabont"])
        #expect(record.castNames == ["演员1", "演员2", "演员3", "演员4", "演员5"])
        #expect(record.imdbID == "tt0111161")
        #expect(record.tmdbRating == 8.7)
        #expect(record.imdbRating == 9.3)
        #expect(record.rottenTomatoesRating == 89)
        #expect(record.posterPath == "/test-poster.jpg")
        #expect(record.posterFilename == "movie-278.jpg")
        #expect(record.watchedOn == watchedOn)
        #expect(record.myRating == 10)
        #expect(record.shortReview == "值得重看。")
        #expect(record.watchedSeason == nil)
        #expect(record.createdAt == addedAt)
        #expect(record.updatedAt == addedAt)
        #expect(record.metadataFetchedAt == addedAt)
    }

    @Test("剧集进度、英文简介标记和缺失评分可持久保存")
    func seriesAndMissingFieldsSurviveReopeningStore() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeSeries(in: directory)

        let reopened = try PersistenceController.makeContainer(in: directory)
        let records = try RecordStore(context: reopened.mainContext).recordsNewestFirst()
        let record = try #require(records.first)
        #expect(records.count == 1)
        #expect(record.mediaKey == "tv:1396")
        #expect(record.mediaType == .tv)
        #expect(record.watchedSeason == 3)
        #expect(record.overviewLanguage == "en")
        #expect(record.overview == "An English overview.")
        #expect(record.creatorNames == ["Vince Gilligan"])
        #expect(record.releaseYear == nil)
        #expect(record.imdbID == nil)
        #expect(record.tmdbRating == nil)
        #expect(record.imdbRating == nil)
        #expect(record.rottenTomatoesRating == nil)
        #expect(record.posterPath == nil)
        #expect(record.posterFilename == nil)
        #expect(record.shortReview.isEmpty)
        #expect(record.genres.isEmpty)
        #expect(record.castNames.isEmpty)
    }

    @Test("重复添加返回已有记录编号，保留原评分与短评")
    func duplicateDoesNotOverwriteExistingRecord() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try PersistenceController.makeContainer(in: directory)
        let store = RecordStore(context: container.mainContext)
        let original = ViewingRecord(tmdbID: 278, mediaType: .movie, title: "原记录", myRating: 10, shortReview: "保留这句话")
        try store.insert(original)
        let duplicate = ViewingRecord(tmdbID: 278, mediaType: .movie, title: "重复记录", myRating: 1, shortReview: "不应覆盖")

        #expect(throws: RecordStore.SaveError.duplicate(existingRecordID: original.id)) {
            try store.insert(duplicate)
        }
        let records = try store.recordsNewestFirst()
        #expect(records.count == 1)
        let match = try store.existingRecord(tmdbID: 278, mediaType: .movie)
        let existing = try #require(match)
        #expect(existing.id == original.id)
        #expect(existing.title == "原记录")
        #expect(existing.myRating == 10)
        #expect(existing.shortReview == "保留这句话")
    }

    @Test("电影和剧集的数字编号相同时仍可分别保存")
    func sameNumericIDForDifferentTypesIsAllowed() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try PersistenceController.makeContainer(in: directory)
        let store = RecordStore(context: container.mainContext)
        try store.insert(ViewingRecord(tmdbID: 123, mediaType: .movie, title: "电影", myRating: 8))
        try store.insert(ViewingRecord(tmdbID: 123, mediaType: .tv, title: "剧集", myRating: 9, watchedSeason: 1))
        #expect(try store.recordsNewestFirst().count == 2)
        #expect(try store.existingRecord(tmdbID: 123, mediaType: .movie)?.title == "电影")
        #expect(try store.existingRecord(tmdbID: 123, mediaType: .tv)?.title == "剧集")
    }

    @Test("列表依据添加时间倒序，不受观看日期影响")
    func recordsUseAddedDateForSorting() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try PersistenceController.makeContainer(in: directory)
        let store = RecordStore(context: container.mainContext)
        try store.insert(ViewingRecord(tmdbID: 1, mediaType: .movie, title: "先添加", watchedOn: Date(timeIntervalSince1970: 300), myRating: 8, createdAt: Date(timeIntervalSince1970: 100)))
        try store.insert(ViewingRecord(tmdbID: 2, mediaType: .movie, title: "后添加", watchedOn: Date(timeIntervalSince1970: 50), myRating: 9, createdAt: Date(timeIntervalSince1970: 200)))
        #expect(try store.recordsNewestFirst().map(\.title) == ["后添加", "先添加"])
    }

    @Test("拒绝保存范围外的个人评分", arguments: [0, 11])
    func invalidPersonalRatingIsRejected(rating: Int) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try PersistenceController.makeContainer(in: directory)
        let store = RecordStore(context: container.mainContext)
        let record = ViewingRecord(tmdbID: 1, mediaType: .movie, title: "测试", myRating: rating)
        #expect(throws: RecordStore.SaveError.invalidRating) {
            try store.insert(record)
        }
        #expect(try store.recordsNewestFirst().isEmpty)
    }

    @Test("观看日期默认今天，电影不保存剧集进度")
    func defaultViewingDateIsToday() {
        let before = Date.now
        let record = ViewingRecord(tmdbID: 1, mediaType: .movie, title: "测试", myRating: 8, watchedSeason: 3)
        let after = Date.now
        #expect(record.watchedOn >= before)
        #expect(record.watchedOn <= after)
        #expect(record.watchedSeason == nil)
    }

    @Test("资料库路径不可用时报告错误并保留原文件")
    func invalidStoreDirectoryDoesNotDestroyOriginalFile() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let blockedDirectory = directory.appendingPathComponent("occupied")
        let original = Data("保留原文件".utf8)
        try original.write(to: blockedDirectory)

        #expect(throws: (any Error).self) {
            _ = try PersistenceController.makeContainer(in: blockedDirectory)
        }
        #expect(try Data(contentsOf: blockedDirectory) == original)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MovieJournalTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func writeMovie(in directory: URL, id: UUID, watchedOn: Date, addedAt: Date) throws {
        let container = try PersistenceController.makeContainer(in: directory)
        let record = ViewingRecord(
            id: id,
            tmdbID: 278,
            mediaType: .movie,
            title: "肖申克的救赎",
            originalTitle: "The Shawshank Redemption",
            releaseYear: 1994,
            genres: ["剧情", "犯罪"],
            overview: "电影简介（测试资料）",
            creatorNames: ["Frank Darabont"],
            castNames: ["演员1", "演员2", "演员3", "演员4", "演员5", "演员6"],
            imdbID: "tt0111161",
            tmdbRating: 8.7,
            imdbRating: 9.3,
            rottenTomatoesRating: 89,
            posterPath: "/test-poster.jpg",
            posterFilename: "movie-278.jpg",
            watchedOn: watchedOn,
            myRating: 10,
            shortReview: "值得重看。",
            createdAt: addedAt,
            metadataFetchedAt: addedAt
        )
        try RecordStore(context: container.mainContext).insert(record)
    }

    private func writeSeries(in directory: URL) throws {
        let container = try PersistenceController.makeContainer(in: directory)
        let record = ViewingRecord(
            tmdbID: 1396,
            mediaType: .tv,
            title: "绝命毒师",
            overview: "An English overview.",
            overviewLanguage: "en",
            creatorNames: ["Vince Gilligan"],
            myRating: 9,
            watchedSeason: 3
        )
        try RecordStore(context: container.mainContext).insert(record)
    }
}
