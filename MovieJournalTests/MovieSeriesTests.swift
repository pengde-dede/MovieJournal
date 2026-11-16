import Foundation
import SwiftData
import Testing
@testable import MovieJournal

@Suite("电影系列合集")
@MainActor
struct MovieSeriesTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func series(id: Int = 17, name: String = "银河合集", posterPath: String? = "/galaxy.jpg") -> MovieSeriesLookup {
        MovieSeriesLookup(series: MovieSeries(id: id, name: name, posterPath: posterPath))
    }

    @Test("添加电影在详情响应中获取合集，补全区分无系列与错误响应")
    func parsesMovieCollection() async throws {
        let response = #"{"id":278,"title":"第一部","overview":"简介","belongs_to_collection":{"id":17,"name":"银河合集","poster_path":"/galaxy.jpg"}}"#
        let transport = ScriptedTransport([
            .json(response), .json(#"{"id":278,"belongs_to_collection":null}"#), .json(response)
        ])
        let client = TMDBClient(transport: transport)
        let details = try await client.details(for: Fixtures.movie, key: "fake-key")
        #expect(details.seriesLookup == series())
        let record = try RecordDraft(details: details).makeRecord()
        #expect(record.movieSeries == details.seriesLookup?.series && !record.needsSeriesLookup)
        #expect(try await client.movieSeries(tmdbID: 278, key: "fake-key").series == nil)
        await #expect(throws: APIError.invalidResponse) {
            try await client.movieSeries(tmdbID: 279, key: "fake-key")
        }
        let requests = await transport.requests
        #expect(requests.map { $0.url?.path } == ["/3/movie/278", "/3/movie/278", "/3/movie/279"])
        #expect(requests[1].url?.query?.contains("append_to_response") == false)
    }

    @Test("旧 V4 迁移保留观影编号和历史，电影可补全，剧集跳过")
    func migratesV4() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let originalID = UUID()
        let originalViewing = UUID()
        let earlier = ViewingEvent(libraryEntryID: originalID, date: nil, rating: 8, review: "初看", season: nil)
        do {
            let schema = Schema(versionedSchema: MovieJournalSchemaV4.self)
            let config = ModelConfiguration("MovieJournal", schema: schema, url: dir.appendingPathComponent("MovieJournal.store"), cloudKitDatabase: .none)
            let original = try ModelContainer(for: schema, configurations: [config])
            original.mainContext.insert(MovieJournalSchemaV4.ViewingRecord(id: originalID, tmdbID: 1, mediaType: .movie,
                title: "旧电影", latestViewingID: originalViewing, myRating: 9, shortReview: "重看"))
            original.mainContext.insert(MovieJournalSchemaV4.ViewingRecord(tmdbID: 1, mediaType: .tv, title: "同编号剧集"))
            original.mainContext.insert(MovieJournalSchemaV4.EarlierViewing(viewing: earlier))
            try original.mainContext.save()
        }
        do {
            let container = try PersistenceController.makeContainer(in: dir)
            let store = RecordStore(context: container.mainContext)
            let movie = try #require(try store.existingRecord(tmdbID: 1, mediaType: .movie))
            let tv = try #require(try store.existingRecord(tmdbID: 1, mediaType: .tv))
            #expect(movie.id == originalID && movie.latestViewingID == originalViewing)
            #expect(movie.myRating == 9 && movie.shortReview == "重看")
            #expect(movie.needsSeriesLookup && !tv.needsSeriesLookup)
            #expect(try container.mainContext.fetch(FetchDescriptor<EarlierViewing>()).first?.viewing == earlier)
        }
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("Backups/BeforeV5.store").path))
    }

    @Test("系列按 ID 折叠，保留单部作品并支持搜索和状态筛选")
    func groupsByIDAndKeepsFilters() throws {
        let second = ViewingRecord(tmdbID: 2, mediaType: .movie, title: "续篇", releaseYear: 2002,
                                   seriesLookup: series(posterPath: nil), watchStatus: .wantToWatch)
        let first = ViewingRecord(tmdbID: 1, mediaType: .movie, title: "初篇", releaseYear: 1999, seriesLookup: series())
        let sameName = ViewingRecord(tmdbID: 3, mediaType: .movie, title: "另一系列", seriesLookup: series(id: 18))
        let tv = ViewingRecord(tmdbID: 1, mediaType: .tv, title: "剧集")
        let library = [second, sameName, first, tv]
        let model = LibraryViewModel()
        let result = model.seriesTiles(matching: library, in: library)
        #expect(result.map(\.id) == [.series(17), .record(sameName.id), .record(tv.id)])
        guard case .series(let group) = try #require(result.first) else { Issue.record("未生成合集"); return }
        #expect(group.series.posterPath == "/galaxy.jpg")
        #expect(group.chronologicalRecords.map(\.id) == [first.id, second.id])
        model.searchText = "银河合集"
        model.statusFilter = .wantToWatch
        let matching = model.matchingRecords(in: library, includeSeriesNames: true)
        let filtered = model.seriesTiles(matching: matching, in: library)
        guard case .series(let filteredGroup) = try #require(filtered.first) else { Issue.record("未保留合集"); return }
        #expect(filteredGroup.libraryCount == 2 && filteredGroup.records.map(\.id) == [second.id])
    }

    @Test("旧片库补全逐部保存，限流后只重试仍待查询的电影")
    func resumableBackfill() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = try PersistenceController.makeContainer(in: dir)
        let store = RecordStore(context: db.mainContext)
        let newer = ViewingRecord(tmdbID: 2, mediaType: .movie, title: "续篇", watchStatus: .watching,
            myRating: 8, shortReview: "保留", createdAt: Date(timeIntervalSince1970: 200))
        let older = ViewingRecord(tmdbID: 1, mediaType: .movie, title: "单片", createdAt: Date(timeIntervalSince1970: 100))
        let tv = ViewingRecord(tmdbID: 3, mediaType: .tv, title: "剧集")
        let watchedID = newer.latestViewingID
        for film in [newer, older, tv] { try store.insert(film) }
        let transport = ScriptedTransport([
            .json(#"{"id":2,"belongs_to_collection":{"id":17,"name":"银河合集","poster_path":"/galaxy.jpg"}}"#),
            .failure(.rateLimited(.tmdb)), .json(#"{"id":1,"belongs_to_collection":null}"#)
        ])
        let catalog = MediaCatalogService(keychain: MemoryKeychain([.tmdb: "fake-key"]), tmdb: TMDBClient(transport: transport))
        let backfill = MovieSeriesBackfill()
        let task = try #require(backfill.start(store: store, catalog: catalog))
        #expect(backfill.start(store: store, catalog: catalog) == nil)
        await task.value
        #expect(newer.seriesLookup == series() && older.needsSeriesLookup)
        #expect(backfill.completed == 1 && backfill.total == 2)
        #expect(backfill.message?.contains("频繁") == true)
        await backfill.start(store: store, catalog: catalog)?.value
        #expect(older.seriesLookup == MovieSeriesLookup(series: nil) && !older.needsSeriesLookup)
        #expect(newer.latestViewingID == watchedID && newer.watchStatus == .watching && newer.myRating == 8 && newer.shortReview == "保留")
        #expect(await transport.requests.map { $0.url?.path } == ["/3/movie/2", "/3/movie/1", "/3/movie/1"])
        #expect(backfill.start(store: store, catalog: catalog) == nil)
        let reopened = try PersistenceController.makeContainer(in: dir)
        #expect(try RecordStore(context: reopened.mainContext).recordsNewestFirst().allSatisfy { !$0.needsSeriesLookup })
    }

    @Test("合集封面随备份恢复，离线可读，最后一个引用删除后才清理")
    func coverSurvivesBackupAndCleanup() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try PersistenceController.makeContainer(in: dir.appendingPathComponent("source"))
        let first = ViewingRecord(tmdbID: 1, mediaType: .movie, title: "第一部", seriesLookup: series())
        let second = ViewingRecord(tmdbID: 2, mediaType: .movie, title: "第二部", seriesLookup: series())
        let store = RecordStore(context: source.mainContext)
        try store.insert(first)
        try store.insert(second)
        let coverPath = try #require(first.seriesPosterPath)
        let transport = PosterTransport([.success(HTTPResponse(data: PosterFixtures.png, statusCode: 200))])
        let cache = PosterCache(directory: dir.appendingPathComponent("images"), transport: transport)
        let cover = try await cache.load(path: coverPath, filename: nil)
        let snapshot = try await LibraryBackup.snapshot(context: source.mainContext, cache: cache)
        #expect(snapshot.posters == [cover.filename: PosterFixtures.png])
        let backup = try JSONDecoder().decode(LibraryBackup.self, from: JSONEncoder().encode(snapshot))
        let target = try PersistenceController.makeContainer(in: dir.appendingPathComponent("target"))
        let offline = PosterTransport([])
        let targetCache = PosterCache(directory: dir.appendingPathComponent("restoredImages"), transport: offline)
        #expect(try await backup.restore(context: target.mainContext, cache: targetCache) == 2)
        let targetStore = RecordStore(context: target.mainContext)
        #expect(try targetStore.recordsNewestFirst().allSatisfy { $0.seriesLookup == series() })
        let cleanup = PosterCleanupCoordinator(cache: targetCache)
        try targetStore.delete(recordID: first.id)
        cleanup.requestCleanup(store: targetStore)
        await cleanup.cleanupTask?.value
        #expect(try await targetCache.load(path: coverPath, filename: nil).data == PosterFixtures.png)
        #expect(await offline.requests.isEmpty)
        try targetStore.delete(recordID: second.id)
        cleanup.requestCleanup(store: targetStore)
        await cleanup.cleanupTask?.value
        #expect(await targetCache.existingFilename(path: coverPath, filename: nil) == nil)
    }
}
