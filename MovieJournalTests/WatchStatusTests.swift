import CoreData
import Foundation
import SwiftData
import Testing
@testable import MovieJournal

@Suite("片单状态与可选评分")
@MainActor
struct WatchStatusTests {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("MovieJournalStatus-\(UUID().uuidString)")
    }

    @Test("三种状态的电影和剧集均可不评分、不记日期和季数", arguments: WatchStatus.allCases, MediaType.allCases)
    func optionalFieldsSurviveReopening(status: WatchStatus, type: MediaType) throws {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let container = try PersistenceController.makeContainer(in: dir)
        let details = Fixtures.details(type == .movie ? Fixtures.movie : Fixtures.series)
        let draft = RecordDraft(details: details, watchStatus: status, watchedOn: nil)
        #expect(draft.validationMessage == nil)
        let record = try draft.makeRecord()
        try RecordStore(context: container.mainContext).insert(record)
        let reopened = try PersistenceController.makeContainer(in: dir)
        let saved = try #require(RecordStore(context: reopened.mainContext).recordsNewestFirst().first)
        #expect(saved.watchStatus == status)
        #expect(saved.myRating == nil && saved.watchedOn == nil && saved.watchedSeason == nil)
    }

    @Test("添加默认想看，可直接保存，状态修改触发草稿保护")
    func addStartsInWatchlist() async throws {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let container = try PersistenceController.makeContainer(in: dir)
        let store = RecordStore(context: container.mainContext)
        let model = AddRecordViewModel(catalog: ImmediateCatalog(), store: store, posters: StubPosterCache())
        defer { model.cancelPendingWork() }
        await model.select(Fixtures.movie).value
        #expect(model.draft?.watchStatus == .wantToWatch && model.draft?.watchedOn == nil)
        #expect(!model.hasPersonalEdits)
        model.draft?.changeStatus(to: .watching)
        #expect(model.hasPersonalEdits)
        model.draft?.changeStatus(to: .wantToWatch)
        #expect(!model.hasPersonalEdits)
        #expect(model.saveRecord() != nil)
        let record = try #require(store.recordsNewestFirst().first)
        #expect(record.myRating == nil && record.watchStatus == .wantToWatch)
        #expect(model.saveRecord() == nil)
    }

    @Test("状态流转不生成重复作品，标为已看可稍后评分")
    func transitionsKeepIdentityAndOptionalRating() throws {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let container = try PersistenceController.makeContainer(in: dir)
        let store = RecordStore(context: container.mainContext)
        let record = ViewingRecord(tmdbID: 1, mediaType: .movie, title: "片单", watchStatus: .wantToWatch, watchedOn: nil)
        try store.insert(record)
        try store.setWatchStatus(.watching, recordID: record.id)
        #expect(record.watchStatus == .watching && record.watchedOn == nil)
        try store.setWatchStatus(.watched, recordID: record.id)
        #expect(record.watchStatus == .watched && record.watchedOn != nil && record.myRating == nil)
        let edit = EditRecordViewModel(record: record, store: store)
        edit.draft.myRating = 8
        #expect(edit.save())
        let clear = EditRecordViewModel(record: record, store: store)
        clear.draft.myRating = nil
        clear.draft.watchedOn = nil
        #expect(clear.save())
        let reopened = try PersistenceController.makeContainer(in: dir)
        let saved = try #require(RecordStore(context: reopened.mainContext).recordsNewestFirst().first)
        #expect(saved.id == record.id && saved.watchStatus == .watched && saved.myRating == nil && saved.watchedOn == nil)
        #expect(try store.recordsNewestFirst().count == 1)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<EarlierViewing>()) == 0)
    }

    @Test("更改状态保留个人内容与历史；未评分重看也可保存")
    func transitionsPreserveViewingHistory() throws {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let container = try PersistenceController.makeContainer(in: dir)
        let store = RecordStore(context: container.mainContext)
        let record = ViewingRecord(tmdbID: 2, mediaType: .tv, title: "剧集", watchedOn: Date(timeIntervalSince1970: 100), myRating: 9, shortReview: "初看", watchedSeason: 2)
        try store.insert(record)
        var rewatch = RecordDraft(details: MediaDetails(record: record))
        rewatch.watchedOn = Date(timeIntervalSince1970: 200)
        try store.addViewing(recordID: record.id, draft: rewatch)
        #expect(record.myRating == nil)
        for status in WatchStatus.allCases { try store.setWatchStatus(status, recordID: record.id) }
        let history = try container.mainContext.fetch(FetchDescriptor<EarlierViewing>())
        #expect(history.count == 1 && history.first?.rating == 9 && history.first?.review == "初看")
        #expect(record.watchedOn == rewatch.watchedOn && record.watchedSeason == nil)
        try store.setWatchStatus(.watching, recordID: record.id)
        #expect(throws: RecordStore.SaveError.invalidViewing) { try store.addViewing(recordID: record.id, draft: rewatch) }
    }

    @Test("状态保存失败回滚，已删除记录不能复活")
    func failedStatusChangeRollsBack() throws {
        enum Failure: Error { case write }
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let container = try PersistenceController.makeContainer(in: dir)
        let store = RecordStore(context: container.mainContext)
        let record = ViewingRecord(tmdbID: 3, mediaType: .movie, title: "片单", watchStatus: .wantToWatch, watchedOn: nil)
        try store.insert(record)
        let oldUpdate = record.updatedAt
        let broken = RecordStore(context: container.mainContext) { throw Failure.write }
        #expect(throws: Failure.self) { try broken.setWatchStatus(.watched, recordID: record.id) }
        #expect(record.watchStatus == .wantToWatch && record.watchedOn == nil && record.updatedAt == oldUpdate)
        #expect(!container.mainContext.hasChanges)
        let id = record.id
        try store.delete(recordID: id)
        #expect(throws: RecordStore.SaveError.recordNotFound) { try store.setWatchStatus(.watched, recordID: id) }
    }

    @Test("状态、类型、搜索叠加筛选，未评分和无日期排在最后")
    func filteringAndNilSorting() {
        let wanted = ViewingRecord(tmdbID: 1, mediaType: .movie, title: "A", watchStatus: .wantToWatch, watchedOn: nil)
        let watching = ViewingRecord(tmdbID: 2, mediaType: .tv, title: "B", watchStatus: .watching, watchedOn: nil)
        let watched = ViewingRecord(tmdbID: 3, mediaType: .movie, title: "C", myRating: 7)
        let records = [wanted, watching, watched]
        let model = LibraryViewModel()
        #expect(model.matchingRecords(in: records, sort: .rating).first?.id == watched.id)
        #expect(model.matchingRecords(in: records, sort: .watched).first?.id == watched.id)
        model.statusFilter = .watching
        #expect(model.matchingRecords(in: records).map(\.id) == [watching.id])
        model.mediaFilter = .movie
        #expect(model.matchingRecords(in: records).isEmpty)
        model.resetFilters()
        model.statusFilter = .watched
        model.searchText = "C"
        #expect(model.matchingRecords(in: records).map(\.id) == [watched.id])
        model.resetFilters()
        #expect(model.matchingRecords(in: records).count == 3)
    }

    @Test("新版备份保留全部状态和空评分，重复恢复不会覆盖本机")
    func newBackupRoundTrip() async throws {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try PersistenceController.makeContainer(in: dir.appendingPathComponent("source"))
        let targetDir = dir.appendingPathComponent("target")
        let target = try PersistenceController.makeContainer(in: targetDir)
        let cache = PosterCache(directory: dir.appendingPathComponent("images"))
        let store = RecordStore(context: source.mainContext)
        for (index, status) in WatchStatus.allCases.enumerated() {
            try store.insert(ViewingRecord(tmdbID: index + 1, mediaType: .tv, title: status.title, watchStatus: status, watchedOn: nil))
        }
        let watched = try #require(store.recordsNewestFirst().first { $0.watchStatus == .watched })
        var rewatch = RecordDraft(details: MediaDetails(record: watched))
        rewatch.watchedOn = nil
        try store.addViewing(recordID: watched.id, draft: rewatch)
        let snapshot = try await LibraryBackup.snapshot(context: source.mainContext, cache: cache)
        let backup = try JSONDecoder().decode(LibraryBackup.self, from: JSONEncoder().encode(snapshot))
        #expect(backup.version == 3)
        #expect(try await backup.restore(context: target.mainContext, cache: cache) == 3)
        try RecordStore(context: target.mainContext).setWatchStatus(.watching, recordID: watched.id)
        #expect(try await backup.restore(context: target.mainContext, cache: cache) == 0)
        let reopened = try PersistenceController.makeContainer(in: targetDir)
        let saved = try RecordStore(context: reopened.mainContext).recordsNewestFirst()
        #expect(saved.count == 3 && saved.allSatisfy { $0.myRating == nil && $0.watchedOn == nil })
        #expect(saved.first { $0.id == watched.id }?.watchStatus == .watching)
        #expect(try reopened.mainContext.fetchCount(FetchDescriptor<EarlierViewing>()) == 1)
        #expect(saved.contains { $0.watchStatus == .wantToWatch })
    }

    @Test("旧 JSON 没有状态字段时恢复为已看，非法新备份不得部分写入")
    func oldBackupAndInvalidArchives() async throws {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let target = try PersistenceController.makeContainer(in: dir)
        let cache = PosterCache(directory: dir.appendingPathComponent("images"))
        let visit = LibraryBackup.Visit(date: Date(timeIntervalSince1970: 100), rating: 8, review: "旧备份", season: nil)
        let entry = LibraryBackup.Entry(id: UUID(), details: Fixtures.details(Fixtures.movie), created: .now, updated: .now, latest: visit, history: [], filename: nil)
        let old = LibraryBackup(version: 1, entries: [entry], posters: [:])
        let data = try JSONEncoder().encode(old)
        #expect(!String(decoding: data, as: UTF8.self).contains("status"))
        let decoded = try JSONDecoder().decode(LibraryBackup.self, from: data)
        #expect(try await decoded.restore(context: target.mainContext, cache: cache) == 1)
        let restored = try #require(RecordStore(context: target.mainContext).recordsNewestFirst().first)
        #expect(restored.watchStatus == .watched && restored.myRating == 8)
        #expect(restored.latestViewingID != nil)
        var malformed = old
        malformed.version = 2
        #expect(throws: LibraryBackup.Invalid.self) { try malformed.additions(to: target.mainContext) }
        malformed.entries[0].status = .watching
        malformed.entries[0].latest.rating = 0
        #expect(throws: LibraryBackup.Invalid.self) { try malformed.additions(to: target.mainContext) }
        #expect(try RecordStore(context: target.mainContext).recordsNewestFirst().count == 1)
    }

    @Test("给未知日期的重看补日期后，历史仍能备份恢复")
    func datedHistoryIsPromotedWhenNeeded() async throws {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let container = try PersistenceController.makeContainer(in: dir)
        let store = RecordStore(context: container.mainContext)
        let record = ViewingRecord(tmdbID: 4, mediaType: .movie, title: "历史", watchedOn: Date(timeIntervalSince1970: 300), myRating: 9)
        try store.insert(record)
        var draft = RecordDraft(details: MediaDetails(record: record))
        draft.watchedOn = nil
        try store.addViewing(recordID: record.id, draft: draft)
        draft.watchedOn = Date(timeIntervalSince1970: 200)
        try store.addViewing(recordID: record.id, draft: draft)
        #expect(record.watchedOn == Date(timeIntervalSince1970: 300) && record.myRating == 9)
        let cache = PosterCache(directory: dir.appendingPathComponent("images"))
        let backup = try await LibraryBackup.snapshot(context: container.mainContext, cache: cache)
        _ = try backup.additions(to: container.mainContext)
    }

    @Test("真实 V2 数据库升级保留作品和重看历史，升级前快照可由 V2 重开")
    func migrateV2AndReopenSnapshot() throws {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let id = UUID()
        func openV2(_ url: URL) throws -> ModelContainer {
            let schema = Schema(versionedSchema: MovieJournalSchemaV2.self)
            let config = ModelConfiguration("MovieJournal", schema: schema, url: url, cloudKitDatabase: .none)
            return try ModelContainer(for: schema, configurations: [config])
        }
        do {
            let old = try openV2(dir.appendingPathComponent("MovieJournal.store"))
            old.mainContext.insert(MovieJournalSchemaV1.ViewingRecord(id: id, tmdbID: 20, mediaType: .tv, title: "旧记录", watchedOn: Date(timeIntervalSince1970: 200), myRating: 9, shortReview: "重看", watchedSeason: 3))
            old.mainContext.insert(MovieJournalSchemaV2.EarlierViewing(recordID: id, watchedOn: Date(timeIntervalSince1970: 100), rating: 8, review: "初看", season: 2))
            try old.mainContext.save()
        }
        // Hashes generated from the published 1.1.1 models at commit 3d21346, before introducing V3.
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
            ofType: NSSQLiteStoreType, at: dir.appendingPathComponent("MovieJournal.store"))
        let hashes = try #require(metadata[NSStoreModelVersionHashesKey] as? [String: Data])
        #expect(hashes["ViewingRecord"]?.base64EncodedString() == "Wk48dXD3KlFStj5dWCtLI/XWEpkILNpJdQ4NzhmZ6MY=")
        #expect(hashes["EarlierViewing"]?.base64EncodedString() == "MMRLjSCKlwzEfNX63COkyF7Xzb0zROfYaMlWw2rtDz4=")
        let current = try PersistenceController.makeContainer(in: dir)
        let item = try #require(RecordStore(context: current.mainContext).recordsNewestFirst().first)
        #expect(item.id == id && item.watchStatus == .watched && item.myRating == 9 && item.shortReview == "重看" && item.watchedSeason == 3)
        let history = try current.mainContext.fetch(FetchDescriptor<EarlierViewing>())
        #expect(history.count == 1 && history.first?.recordID == id && history.first?.rating == 8)
        #expect(item.latestViewingID != nil && history.first?.viewingID != nil)
        let snapshot = dir.appendingPathComponent("Backups/BeforeV3.store")
        let originalBytes = try Data(contentsOf: snapshot)
        let before = try openV2(snapshot)
        #expect(try before.mainContext.fetch(FetchDescriptor<MovieJournalSchemaV1.ViewingRecord>()).first?.id == id)
        #expect(try before.mainContext.fetchCount(FetchDescriptor<MovieJournalSchemaV2.EarlierViewing>()) == 1)
        _ = try PersistenceController.makeContainer(in: dir)
        #expect(try Data(contentsOf: snapshot) == originalBytes)
    }
}
