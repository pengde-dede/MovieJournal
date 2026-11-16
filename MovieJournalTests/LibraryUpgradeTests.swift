import Foundation
import SwiftData
import Testing
@testable import MovieJournal

@MainActor
struct LibraryUpgradeTests {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func openV1(_ url: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: MovieJournalSchemaV1.self)
        let config = ModelConfiguration("MovieJournal", schema: schema, url: url, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @Test func migrationPreservesOriginalAndCreatesReadableSnapshot() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = UUID()
        do {
            let old = try openV1(dir.appendingPathComponent("MovieJournal.store"))
            let record = MovieJournalSchemaV1.ViewingRecord(id: id, tmdbID: 123, mediaType: .movie, title: "测试电影", myRating: 8, shortReview: "初看")
            old.mainContext.insert(record)
            try old.mainContext.save()
        }
        let current = try PersistenceController.makeContainer(in: dir)
        let item = try #require(current.mainContext.fetch(FetchDescriptor<ViewingRecord>()).first)
        #expect(item.id == id && item.shortReview == "初看")
        #expect(item.latestViewing?.id != nil && item.latestViewing?.rating == 8)
        let before = try openV1(dir.appendingPathComponent("Backups/BeforeV2.store"))
        #expect(try before.mainContext.fetch(FetchDescriptor<MovieJournalSchemaV1.ViewingRecord>()).first?.id == id)
    }

    @Test func draftProtectionTracksPersonalChangesOnly() async throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let container = try PersistenceController.makeContainer(in: dir)
        let model = AddRecordViewModel(catalog: ImmediateCatalog(), store: RecordStore(context: container.mainContext), posters: StubPosterCache())
        await model.select(Fixtures.movie).value
        #expect(!model.hasPersonalEdits)
        let original = Date(timeIntervalSince1970: 1_793_030_400)
        model.draft?.watchedOn = original.addingTimeInterval(-86400)
        #expect(model.hasPersonalEdits)
        model.draft?.watchedOn = nil
        model.draft?.shortReview = "保留草稿"
        #expect(model.hasPersonalEdits)
        await model.posterTask?.value
        #expect(model.draft?.shortReview == "保留草稿")
    }

    @Test func sortChoicesRespectFilters() {
        let movie = ViewingRecord(tmdbID: 1, mediaType: .movie, title: "A", watchedOn: Date(timeIntervalSince1970: 1), myRating: 10)
        let tv = ViewingRecord(tmdbID: 2, mediaType: .tv, title: "B", watchedOn: Date(timeIntervalSince1970: 2), myRating: 7)
        let model = LibraryViewModel()
        #expect(model.matchingRecords(in: [movie, tv], sort: .watched).first?.id == tv.id)
        #expect(model.matchingRecords(in: [tv, movie], sort: .rating).first?.id == movie.id)
        model.mediaFilter = .movie
        #expect(model.matchingRecords(in: [tv, movie], sort: .rating).map(\.id) == [movie.id])
    }

    @Test func duplicateSafeRestoreWithPostersAndRewatches() async throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try PersistenceController.makeContainer(in: dir.appendingPathComponent("source"))
        let targetDir = dir.appendingPathComponent("target")
        let dest = try PersistenceController.makeContainer(in: targetDir)
        let srcCache = PosterCache(directory: dir.appendingPathComponent("srcImages"))
        let dstCache = PosterCache(directory: dir.appendingPathComponent("dstImages"))
        let name = try #require(PosterCache.filename(for: "/a.jpg"))
        try await srcCache.restorePoster(PosterFixtures.png, filename: name)
        let store = RecordStore(context: source.mainContext)
        let record = ViewingRecord(tmdbID: 50, mediaType: .movie, title: "电影", posterPath: "/a.jpg", posterFilename: name, myRating: 8, shortReview: "初看")
        try store.insert(record)
        var draft = RecordDraft(details: MediaDetails(record: record))
        draft.myRating = 10
        draft.watchedOn = try #require(record.watchedOn).addingTimeInterval(86400)
        draft.shortReview = "重看"
        try store.addViewing(recordID: record.id, draft: draft)
        draft.watchedOn = try #require(record.watchedOn).addingTimeInterval(-172800)
        try store.addViewing(recordID: record.id, draft: draft)
        let snapshot = try await LibraryBackup.snapshot(context: source.mainContext, cache: srcCache)
        let backup = try JSONDecoder().decode(LibraryBackup.self, from: JSONEncoder().encode(snapshot))
        #expect(try backup.additions(to: dest.mainContext).count == 1)
        #expect(try await backup.restore(context: dest.mainContext, cache: dstCache) == 1)
        #expect(try await backup.restore(context: dest.mainContext, cache: dstCache) == 0)
        #expect(try await dstCache.readData(filename: name) == PosterFixtures.png)
        let reopened = try PersistenceController.makeContainer(in: targetDir)
        let imported = try #require(reopened.mainContext.fetch(FetchDescriptor<ViewingRecord>()).first)
        #expect(imported.id == record.id && imported.shortReview == "重看")
        #expect(imported.myRating == 10 && imported.createdAt == record.createdAt)
        let history = try reopened.mainContext.fetch(FetchDescriptor<EarlierViewing>())
        #expect(history.count == 2 && history.contains { $0.review == "初看" && $0.rating == 8 })
        #expect(imported.latestViewingID == record.latestViewingID)
        let backedUp = try #require(backup.entries.first)
        #expect(Set(history.compactMap(\.viewingID)) == Set(backedUp.history.compactMap(\.id)))
        try RecordStore(context: reopened.mainContext).delete(recordID: imported.id)
        #expect(try reopened.mainContext.fetchCount(FetchDescriptor<EarlierViewing>()) == 0)
    }
}
