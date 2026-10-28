import Foundation
import SwiftData
import Testing
@testable import MovieJournal

@Suite("编辑观影记录")
@MainActor
struct RecordEditingTests {
    @Test("编辑使用独立草稿，取消后原记录及磁盘数据不变")
    func editingDoesNotWriteUntilSave() throws {
        let fixture = try database()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let record = try sampleRecord(in: fixture.store, type: .tv)
        let model = EditRecordViewModel(record: record, store: fixture.store)
        #expect(model.draft.details == MediaDetails(record: record))
        #expect(model.draft.watchedSeasonText == "2")
        #expect(model.draft.myRating == 8 && model.draft.shortReview == "原短评")
        model.draft.myRating = 1
        model.draft.shortReview = "取消这些修改"
        model.draft.watchedSeasonText = "第3季"
        #expect(!fixture.container.mainContext.hasChanges)
        let reopened = try PersistenceController.makeContainer(in: fixture.directory)
        let saved = try #require(RecordStore(context: reopened.mainContext).recordsNewestFirst().first)
        #expect(saved.myRating == 8 && saved.shortReview == "原短评" && saved.watchedSeason == 2)
    }

    @Test("电影与剧集修改重开后保留，资料快照、海报和添加顺序不变", arguments: [MediaType.movie, .tv])
    func editsPersistWithoutReplacingMetadata(type: MediaType) throws {
        let fixture = try database()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let record = try sampleRecord(in: fixture.store, type: type)
        let identifier = record.id
        let createdAt = record.createdAt
        let metadata = MediaDetails(record: record)
        let model = EditRecordViewModel(record: record, store: fixture.store)
        let newer = ViewingRecord(tmdbID: 999, mediaType: .movie, title: "后添加", myRating: 6, createdAt: Date(timeIntervalSince1970: 200))
        try fixture.store.insert(newer)
        // 模拟另一窗口补存了海报，旧编辑草稿不能把新引用覆盖回 nil。
        let repaired = try #require(PosterCache.filename(for: record.posterPath))
        try fixture.store.setPosterFilename(repaired, recordID: identifier, expectedPath: record.posterPath)
        model.draft.watchedOn = Date(timeIntervalSince1970: 300)
        model.draft.myRating = 10
        model.draft.shortReview = "  新短评\n"
        model.draft.watchedSeasonText = "３"
        model.draft.details.title = "不能覆盖片名"
        model.draft.details.tmdbRating = 1
        #expect(model.save())
        #expect(!model.save())
        let reopened = try PersistenceController.makeContainer(in: fixture.directory)
        let records = try RecordStore(context: reopened.mainContext).recordsNewestFirst()
        #expect(records.count == 2 && records.map(\.id) == [newer.id, identifier])
        let saved = try #require(records.last)
        #expect(saved.myRating == 10 && saved.shortReview == "新短评")
        #expect(saved.watchedOn == Date(timeIntervalSince1970: 300))
        #expect(saved.watchedSeason == (type == .tv ? 3 : nil))
        #expect(saved.createdAt == createdAt && saved.updatedAt > createdAt)
        #expect(saved.posterFilename == repaired)
        #expect(MediaDetails(record: saved) == metadata)
    }

    @Test("无效评分不能写入并保留草稿", arguments: [0, 11])
    func invalidRatingsCannotReplaceRecord(rating: Int) throws {
        let fixture = try database()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let record = try sampleRecord(in: fixture.store)
        let model = EditRecordViewModel(record: record, store: fixture.store)
        model.draft.myRating = rating
        #expect(!model.save() && model.saveError != nil)
        #expect(model.draft.myRating == rating && record.myRating == 8)
        #expect(throws: RecordStore.SaveError.invalidRating) {
            try fixture.store.updatePersonalInformation(recordID: record.id, watchedOn: .now, myRating: rating, shortReview: "无效", watchedSeason: nil)
        }
        #expect(!fixture.container.mainContext.hasChanges)
    }

    @Test("无效季数保留原文，不覆盖已存进度", arguments: ["", "0", "-1", "第2季", "二"])
    func invalidSeasonKeepsOriginal(text: String) throws {
        let fixture = try database()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let record = try sampleRecord(in: fixture.store, type: .tv)
        let model = EditRecordViewModel(record: record, store: fixture.store)
        model.draft.watchedSeasonText = text
        model.draft.shortReview = "尚未保存"
        #expect(!model.save())
        #expect(model.draft.watchedSeasonText == text && model.saveError != nil)
        #expect(record.watchedSeason == 2 && record.shortReview == "原短评")
        #expect(throws: RecordStore.SaveError.invalidSeason) {
            try fixture.store.updatePersonalInformation(recordID: record.id, watchedOn: .now, myRating: 9, shortReview: "无效", watchedSeason: model.draft.watchedSeason)
        }
        #expect(!fixture.container.mainContext.hasChanges)
    }

    @Test("修改保存失败时回滚所有字段，保留输入并可重试")
    func failedEditRollsBackAndCanRetry() throws {
        let fixture = try database()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let record = try sampleRecord(in: fixture.store, type: .tv)
        let originalDate = record.watchedOn
        let updatedAt = record.updatedAt
        var failSave = true
        let store = RecordStore(context: fixture.container.mainContext) {
            if failSave { throw WriteFailure.unavailable }
            try fixture.container.mainContext.save()
        }
        let model = EditRecordViewModel(record: record, store: store)
        model.draft.watchedOn = .now
        model.draft.myRating = 10
        model.draft.watchedSeasonText = "4"
        model.draft.shortReview = "保留待重试的输入"
        #expect(!model.save() && !model.didSave && model.saveError != nil)
        #expect(record.myRating == 8 && record.shortReview == "原短评" && record.watchedSeason == 2)
        #expect(record.watchedOn == originalDate && record.updatedAt == updatedAt)
        #expect(!fixture.container.mainContext.hasChanges)
        #expect(model.draft.shortReview == "保留待重试的输入")
        failSave = false
        #expect(model.save() && model.saveError == nil)
        let reopened = try PersistenceController.makeContainer(in: fixture.directory)
        let saved = try #require(RecordStore(context: reopened.mainContext).recordsNewestFirst().first)
        #expect(saved.myRating == 10 && saved.watchedSeason == 4 && saved.shortReview == "保留待重试的输入")
    }

    @Test("另一窗口删除记录后，旧编辑草稿不能使记录复活")
    func editingDeletedRecordShowsError() throws {
        let fixture = try database()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let record = try sampleRecord(in: fixture.store)
        let id = record.id
        let model = EditRecordViewModel(record: record, store: fixture.store)
        model.draft.myRating = 10
        try fixture.store.delete(recordID: id)
        #expect(!model.save())
        #expect(model.saveError?.contains("其他窗口删除") == true)
        #expect(try fixture.store.recordsNewestFirst().isEmpty)
        // 删除前尚未结束的海报补存也不能重新创建记录。
        try fixture.store.setPosterFilename("late.image", recordID: id, expectedPath: Fixtures.movie.posterPath)
        let reopened = try PersistenceController.makeContainer(in: fixture.directory)
        #expect(try RecordStore(context: reopened.mainContext).recordsNewestFirst().isEmpty)
    }

    private func sampleRecord(in store: RecordStore, type: MediaType = .movie) throws -> ViewingRecord {
        var draft = RecordDraft(details: Fixtures.details(type == .movie ? Fixtures.movie : Fixtures.series))
        draft.myRating = 8
        draft.shortReview = "原短评"
        draft.watchedSeason = 2
        let record = try draft.makeRecord()
        // 固定添加时间，测试编辑后不会改变列表位置。
        let saved = ViewingRecord(tmdbID: record.tmdbID, mediaType: type, title: record.title,
            originalTitle: record.originalTitle, releaseYear: record.releaseYear, genres: record.genres,
            overview: record.overview, overviewLanguage: record.overviewLanguage, creatorNames: record.creatorNames,
            castNames: record.castNames, imdbID: record.imdbID, tmdbRating: record.tmdbRating,
            imdbRating: 9.1, rottenTomatoesRating: 90, posterPath: record.posterPath,
            watchedOn: Date(timeIntervalSince1970: 150), myRating: record.myRating, shortReview: record.shortReview,
            watchedSeason: record.watchedSeason, createdAt: Date(timeIntervalSince1970: 100), metadataFetchedAt: record.metadataFetchedAt)
        try store.insert(saved)
        return saved
    }

    private func database() throws -> (directory: URL, container: ModelContainer, store: RecordStore) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MovieJournalEditingTests-\(UUID().uuidString)", isDirectory: true)
        let container = try PersistenceController.makeContainer(in: directory)
        return (directory, container, RecordStore(context: container.mainContext))
    }
}

private enum WriteFailure: Error { case unavailable }
