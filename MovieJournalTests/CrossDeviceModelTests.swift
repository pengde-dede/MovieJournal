import Foundation
import SwiftData
import Testing
@testable import MovieJournal

@MainActor
struct CrossDeviceModelTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func openV3(_ url: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: MovieJournalSchemaV3.self)
        let config = ModelConfiguration("MovieJournal", schema: schema, url: url, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @Test("V3 数据库升级保留资料、收藏和每次观看，重开不重新分配编号")
    func migrateV3AndReopen() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let watchedID = UUID()
        let date = Date(timeIntervalSince1970: 250.125)
        let created = Date(timeIntervalSince1970: 150)
        let updated = Date(timeIntervalSince1970: 275)
        let poster = try #require(PosterCache.filename(for: "/legacy.jpg"))
        let details = MediaDetails(tmdbID: 21, mediaType: .tv, title: "旧剧集", originalTitle: "Series",
            releaseYear: 2019, genres: ["剧情"], overview: "摘要", overviewLanguage: "zh-CN", creatorNames: ["主创"],
            castNames: ["主演"], imdbID: "tt0000021", tmdbRating: 8.1, imdbRating: 8.3,
            rottenTomatoesRating: 91, posterPath: "/legacy.jpg", fetchedAt: created, informationNote: nil)
        do {
            let old = try openV3(dir.appendingPathComponent("MovieJournal.store"))
            let watched = MovieJournalSchemaV3.ViewingRecord(id: watchedID, tmdbID: details.tmdbID,
                mediaType: details.mediaType, title: details.title, originalTitle: details.originalTitle,
                releaseYear: details.releaseYear, genres: details.genres, overview: details.overview,
                overviewLanguage: details.overviewLanguage, creatorNames: details.creatorNames, castNames: details.castNames,
                imdbID: details.imdbID, tmdbRating: details.tmdbRating, imdbRating: details.imdbRating,
                rottenTomatoesRating: details.rottenTomatoesRating, posterPath: details.posterPath, posterFilename: poster,
                watchedOn: date, myRating: 9, shortReview: "重看", watchedSeason: 3,
                createdAt: created, metadataFetchedAt: created)
            watched.updatedAt = updated
            old.mainContext.insert(watched)
            old.mainContext.insert(MovieJournalSchemaV3.ViewingRecord(tmdbID: 21, mediaType: .movie, title: "想看",
                watchStatus: .wantToWatch, watchedOn: nil))
            old.mainContext.insert(MovieJournalSchemaV3.ViewingRecord(tmdbID: 22, mediaType: .tv, title: "在看",
                watchStatus: .watching, watchedOn: nil, watchedSeason: 2))
            old.mainContext.insert(MovieJournalSchemaV3.ViewingRecord(tmdbID: 23, mediaType: .movie, title: "已看无日期",
                watchedOn: nil))
            for _ in 0..<2 {
                old.mainContext.insert(MovieJournalSchemaV3.EarlierViewing(recordID: watchedID, watchedOn: nil,
                    rating: nil, review: "早期观看", season: 1))
            }
            try old.mainContext.save()
        }
        let expectedIDs: Set<UUID>
        let expectedEntry: LibraryEntry
        do {
            let current = try PersistenceController.makeContainer(in: dir)
            let store = RecordStore(context: current.mainContext)
            #expect(try store.recordsNewestFirst().count == 4)
            let watched = try #require(try store.existingRecord(tmdbID: 21, mediaType: .tv))
            let latest = try #require(watched.latestViewing)
            let history = try current.mainContext.fetch(FetchDescriptor<EarlierViewing>()).map { row in
                try #require(row.viewing)
            }
            expectedIDs = Set(history.map(\.id) + [latest.id])
            expectedEntry = watched.libraryEntry
            #expect(MediaDetails(record: watched) == details && watched.posterFilename == poster)
            #expect(expectedEntry == LibraryEntry(id: watchedID, mediaKey: "tv:21", status: .watched,
                createdAt: created, updatedAt: updated, latestViewingID: latest.id))
            #expect(latest.libraryEntryID == watchedID && latest.date == date && latest.rating == 9)
            #expect(latest.review == "重看" && latest.season == 3)
            #expect(history.count == 2 && expectedIDs.count == 3)
            #expect(history.allSatisfy { $0.libraryEntryID == watchedID && $0.date == nil && $0.rating == nil
                && $0.review == "早期观看" && $0.season == 1 })
            let wanted = try #require(try store.existingRecord(tmdbID: 21, mediaType: .movie))
            #expect(wanted.libraryEntry.status == .wantToWatch && wanted.latestViewing == nil)
            let watching = try #require(try store.existingRecord(tmdbID: 22, mediaType: .tv))
            #expect(watching.libraryEntry.status == .watching && watching.latestViewing?.season == 2)
            let undated = try #require(try store.existingRecord(tmdbID: 23, mediaType: .movie))
            #expect(undated.latestViewing != nil && undated.latestViewing?.date == nil && undated.myRating == nil)
        }
        let backupURL = dir.appendingPathComponent("Backups/BeforeV4.store")
        let backupBytes = try Data(contentsOf: backupURL)
        do {
            let snapshot = try openV3(backupURL)
            #expect(try snapshot.mainContext.fetchCount(FetchDescriptor<MovieJournalSchemaV3.ViewingRecord>()) == 4)
            #expect(try snapshot.mainContext.fetchCount(FetchDescriptor<MovieJournalSchemaV3.EarlierViewing>()) == 2)
        }
        let reopened = try PersistenceController.makeContainer(in: dir)
        let item = try #require(try RecordStore(context: reopened.mainContext).existingRecord(tmdbID: 21, mediaType: .tv))
        let ids = try reopened.mainContext.fetch(FetchDescriptor<EarlierViewing>()).compactMap(\.viewingID)
        #expect(item.libraryEntry == expectedEntry)
        let latestID = try #require(item.latestViewingID)
        #expect(Set(ids + [latestID]) == expectedIDs)
        #expect(try Data(contentsOf: backupURL) == backupBytes)
    }

    @Test("标记已看后生成编号，重看和调整日期时编号跟随原观看记录")
    func viewingIdentityFollowsEvent() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let container = try PersistenceController.makeContainer(in: dir)
        let context = container.mainContext
        let store = RecordStore(context: context)
        let record = ViewingRecord(tmdbID: 21, mediaType: .tv, title: "追剧", watchStatus: .wantToWatch, watchedOn: nil)
        try store.insert(record)
        #expect(record.latestViewingID == nil)
        try store.setWatchStatus(.watched, recordID: record.id)
        let first = try #require(record.latestViewingID)
        try store.updatePersonalInformation(recordID: record.id, watchedOn: Date(timeIntervalSince1970: 100),
            myRating: nil, shortReview: "初看", watchedSeason: 1)
        #expect(record.latestViewingID == first)
        var draft = RecordDraft(details: MediaDetails(record: record))
        draft.watchedOn = Date(timeIntervalSince1970: 300)
        draft.shortReview = "重看"
        draft.watchedSeason = 2
        try store.addViewing(recordID: record.id, draft: draft)
        let second = try #require(record.latestViewingID)
        #expect(first != second)
        let earlier = try #require(context.fetch(FetchDescriptor<EarlierViewing>()).first)
        #expect(earlier.viewingID == first && earlier.review == "初看")
        // A rejected save must not leave the original event moved or its ID replaced.
        let failing = RecordStore(context: context, saveChanges: { throw CocoaError(.fileWriteOutOfSpace) })
        #expect(throws: CocoaError.self) { try failing.addViewing(recordID: record.id, draft: draft) }
        #expect(record.latestViewingID == second && record.shortReview == "重看")
        #expect(try context.fetchCount(FetchDescriptor<EarlierViewing>()) == 1)
        try store.updatePersonalInformation(recordID: record.id, watchedOn: Date(timeIntervalSince1970: 50),
            myRating: 8, shortReview: "修正重看日期", watchedSeason: 2)
        #expect(record.latestViewingID == first && record.shortReview == "初看")
        #expect(earlier.viewingID == second && earlier.review == "修正重看日期" && earlier.rating == 8)
        try store.setWatchStatus(.watching, recordID: record.id)
        #expect(record.latestViewingID == first)
    }

    @Test("版本 2 JSON 恢复可选个人数据和历史，并为旧记录生成持久编号")
    func importV2Backup() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let target = try PersistenceController.makeContainer(in: dir)
        let cache = PosterCache(directory: dir.appendingPathComponent("images"))
        let entry = LibraryBackup.Entry(id: UUID(), details: Fixtures.details(Fixtures.series), created: .now, updated: .now,
            latest: .init(date: nil, rating: nil, review: "在看", season: 3),
            history: [.init(date: Date(timeIntervalSince1970: 100), rating: 8, review: "第一季", season: 1)],
            filename: nil, status: .watching)
        let data = try JSONEncoder().encode(LibraryBackup(version: 2, entries: [entry], posters: [:]))
        let backup = try JSONDecoder().decode(LibraryBackup.self, from: data)
        #expect(backup.entries[0].latest.id == nil && backup.entries[0].history[0].id == nil)
        #expect(try await backup.restore(context: target.mainContext, cache: cache) == 1)
        #expect(try await backup.restore(context: target.mainContext, cache: cache) == 0)
        let snapshot = try await LibraryBackup.snapshot(context: target.mainContext, cache: cache)
        let current = try #require(snapshot.entries.first)
        #expect(current.id == entry.id && current.status == .watching)
        #expect(current.latest.date == nil && current.latest.rating == nil && current.latest.season == 3)
        #expect(current.latest.id != nil && current.history.first?.id != nil)
        #expect(current.latest.id != current.history.first?.id && current.history.first?.review == "第一季")
        let reopened = try PersistenceController.makeContainer(in: dir)
        let reopenedSnapshot = try await LibraryBackup.snapshot(context: reopened.mainContext, cache: cache)
        #expect(reopenedSnapshot.entries.first?.latest.id == current.latest.id)
        #expect(reopenedSnapshot.entries.first?.history.first?.id == current.history.first?.id)
    }

    @Test("版本 3 备份拒绝缺失或冲突的观看编号，不写入部分片库")
    func rejectsInvalidViewingIDs() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let target = try PersistenceController.makeContainer(in: dir)
        let cache = PosterCache(directory: dir.appendingPathComponent("images"))
        let latestID = UUID()
        let entry = LibraryBackup.Entry(id: UUID(), details: Fixtures.details(Fixtures.movie), created: .now, updated: .now,
            latest: .init(date: nil, rating: nil, review: "", season: nil, id: latestID),
            history: [.init(date: nil, rating: nil, review: "", season: nil, id: latestID)],
            filename: nil, status: .watched)
        var archive = LibraryBackup(entries: [entry], posters: [:])
        await #expect(throws: LibraryBackup.Invalid.self) {
            try await archive.restore(context: target.mainContext, cache: cache)
        }
        archive.entries[0].history[0].id = nil
        #expect(throws: LibraryBackup.Invalid.self) { try archive.additions(to: target.mainContext) }
        archive.entries[0].history = []
        archive.entries[0].latest.id = nil
        #expect(throws: LibraryBackup.Invalid.self) { try archive.additions(to: target.mainContext) }
        #expect(try target.mainContext.fetchCount(FetchDescriptor<ViewingRecord>()) == 0)
    }
}
