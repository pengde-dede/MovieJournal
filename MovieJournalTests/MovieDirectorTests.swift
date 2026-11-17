import Foundation
import SwiftData
import Testing
@testable import MovieJournal

@Suite("电影导演合集")
@MainActor
struct MovieDirectorTests {
    private func directory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func director(_ id: Int, profile: String? = nil, originalName: String? = nil) -> MovieDirector {
        MovieDirector(id: id, name: "同名导演", originalName: originalName, profilePath: profile)
    }

    @Test("完整详情与旧片库补全只解析有效导演，保留同名和联合执导")
    func parsesDirectorCredits() async throws {
        let crew = #"[{"job":"Director","id":11,"name":"同名导演","original_name":"Director A","profile_path":"/a.jpg"},{"job":"Director","id":11,"name":"同名导演"},{"job":"Director","id":22,"name":"同名导演"},{"job":"Producer","id":33,"name":"制片人"},{"job":"Director","id":0,"name":"无效"}]"#
        let transport = ScriptedTransport([
            .json("{\"id\":278,\"title\":\"影片\",\"overview\":\"简介\",\"credits\":{\"crew\":\(crew)}}"),
            .json("{\"id\":278,\"crew\":\(crew)}"),
            .json(#"{"id":278,"crew":[]}"#),
            .json(#"{"id":278,"cast":[]}"#)
        ])
        let client = TMDBClient(transport: transport)
        let expected = [director(11, profile: "/a.jpg", originalName: "Director A"), director(22)]
        let details = try await client.details(for: Fixtures.movie, key: "fake-key")
        #expect(details.movieDirectors == expected)
        #expect(try RecordDraft(details: details).makeRecord().movieDirectors == expected)
        #expect(try await client.movieDirectors(tmdbID: 278, key: "fake-key") == expected)
        #expect(try await client.movieDirectors(tmdbID: 278, key: "fake-key").isEmpty)
        await #expect(throws: APIError.invalidResponse) {
            try await client.movieDirectors(tmdbID: 278, key: "fake-key")
        }
        #expect(await transport.requests.map { $0.url?.path } == ["/3/movie/278", "/3/movie/278/credits", "/3/movie/278/credits", "/3/movie/278/credits"])
    }

    @Test("同名导演独立，各集合并联合执导作品并遵守筛选")
    func groupsByDirectorID() throws {
        let a = director(11, profile: "/a.jpg", originalName: "Director A")
        let b = director(22)
        let joint = ViewingRecord(tmdbID: 1, mediaType: .movie, title: "合拍", releaseYear: 2002,
                                  movieDirectors: [a, b], watchStatus: .wantToWatch)
        let aOnly = ViewingRecord(tmdbID: 2, mediaType: .movie, title: "早期", releaseYear: 1996, movieDirectors: [a])
        let bOnly = ViewingRecord(tmdbID: 3, mediaType: .movie, title: "晚期", releaseYear: 2005, posterPath: "/film.jpg", movieDirectors: [b])
        let singleton = ViewingRecord(tmdbID: 4, mediaType: .movie, title: "单部", movieDirectors: [director(33)])
        let tv = ViewingRecord(tmdbID: 5, mediaType: .tv, title: "剧集", movieDirectors: [a])
        let library = [joint, aOnly, bOnly, singleton, tv]
        let grouping = LibraryGrouping(records: library, mode: .directors)
        #expect(grouping.tiles(matching: library).map(\.id) == [.director(11), .director(22), .record(singleton.id), .record(tv.id)])
        let groupA = try #require(grouping.group(.director(11), matching: grouping.records(in: .director(11))))
        let groupB = try #require(grouping.group(.director(22), matching: grouping.records(in: .director(22))))
        #expect(groupA.name == groupB.name && groupA.id != groupB.id)
        #expect(groupA.chronologicalRecords.map(\.id) == [aOnly.id, joint.id])
        #expect(groupB.chronologicalRecords.map(\.id) == [joint.id, bOnly.id])
        #expect(groupA.usesProfile && groupA.artworkPath == "/a.jpg")
        #expect(groupB.artworkPath == nil && groupB.posterSources.map(\.id) == [bOnly.id])
        let model = LibraryViewModel()
        model.searchText = "Director A"
        let matches = model.matchingRecords(in: library, displayMode: .directors)
        #expect(matches.map(\.id) == [joint.id, aOnly.id])
        model.statusFilter = .wantToWatch
        let wanted = model.matchingRecords(in: library, displayMode: .directors)
        let filtered = grouping.tiles(matching: wanted)
        guard case .group(let filteredGroup) = try #require(filtered.first) else { Issue.record("未保留导演合集"); return }
        #expect(filteredGroup.libraryCount == 2 && filteredGroup.records.map(\.id) == [joint.id])
    }

    @Test("导演合集优先分区，缺导演资料和单片导演保留在下方")
    func directorSectionsPreserveMembershipAndOrder() {
        let missing = ViewingRecord(tmdbID: 10, mediaType: .movie, title: "待补资料")
        let first = ViewingRecord(tmdbID: 11, mediaType: .movie, title: "甲作品", movieDirectors: [director(1)])
        let single = ViewingRecord(tmdbID: 12, mediaType: .movie, title: "单部作品", movieDirectors: [director(2)])
        let noCredit = ViewingRecord(tmdbID: 13, mediaType: .movie, title: "没有导演资料", movieDirectors: [])
        let second = ViewingRecord(tmdbID: 14, mediaType: .movie, title: "乙作品", movieDirectors: [director(1)])
        let records = [missing, first, single, noCredit, second]
        let directors = LibraryGrouping(records: records, mode: .directors)

        let sections = directors.sections(matching: records)
        #expect(sections.map(\.id) == [.directorGroups, .ungrouped])
        #expect(sections.first?.tiles.map(\.id) == [.director(1)])
        #expect(sections.last?.tiles.map(\.id) == [.record(missing.id), .record(single.id), .record(noCredit.id)])

        // 筛选结果只剩某位导演的一部电影时，仍按整份片库的成员数归组。
        let filtered = directors.sections(matching: [second])
        #expect(filtered.map(\.id) == [.directorGroups])
        #expect(filtered.first?.tiles.map(\.id) == [.director(1)])
        #expect(directors.sections(matching: [single]).map(\.id) == [.ungrouped])
        #expect(directors.sections(matching: []).isEmpty)

        let works = LibraryGrouping(records: records, mode: .works).sections(matching: records)
        #expect(works.map(\.id) == [.plain])
        #expect(works.first?.tiles.map(\.id) == records.map { .record($0.id) })
    }

    @Test("V5 升级保留系列和观影资料，旧电影可补导演")
    func migratesV5() throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID()
        let event = UUID()
        let series = MovieSeriesLookup(series: MovieSeries(id: 70, name: "旧系列", posterPath: "/series.jpg"))
        do {
            let schema = Schema(versionedSchema: MovieJournalSchemaV5.self)
            let configuration = ModelConfiguration("MovieJournal", schema: schema,
                url: directory.appendingPathComponent("MovieJournal.store"), cloudKitDatabase: .none)
            let old = try ModelContainer(for: schema, configurations: [configuration])
            old.mainContext.insert(MovieJournalSchemaV5.ViewingRecord(id: id, tmdbID: 7, mediaType: .movie,
                title: "旧电影", creatorNames: ["旧导演名字"], seriesLookup: series,
                latestViewingID: event, myRating: 8, shortReview: "旧短评"))
            try old.mainContext.save()
        }
        do {
            let current = try PersistenceController.makeContainer(in: directory)
            let record = try #require(try RecordStore(context: current.mainContext).recordsNewestFirst().first)
            #expect(record.id == id && record.latestViewingID == event && record.seriesLookup == series)
            #expect(record.myRating == 8 && record.shortReview == "旧短评" && record.creatorNames == ["旧导演名字"])
            #expect(record.needsLookup(.directors) && !record.needsLookup(.series))
        }
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("Backups/BeforeV6.store").path))
    }

    @Test("补全逐部保存，限流后续传，保留已识别系列和观影事件")
    func resumesDirectorBackfill() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let db = try PersistenceController.makeContainer(in: directory)
        let store = RecordStore(context: db.mainContext)
        let series = MovieSeriesLookup(series: MovieSeries(id: 70, name: "已有系列", posterPath: nil))
        let newer = ViewingRecord(tmdbID: 2, mediaType: .movie, title: "有导演", seriesLookup: series,
            watchStatus: .watching, myRating: 8, shortReview: "保留", createdAt: Date(timeIntervalSince1970: 200))
        let older = ViewingRecord(tmdbID: 1, mediaType: .movie, title: "没有导演", createdAt: Date(timeIntervalSince1970: 100))
        let tv = ViewingRecord(tmdbID: 3, mediaType: .tv, title: "剧集")
        let event = newer.latestViewingID
        for record in [newer, older, tv] { try store.insert(record) }
        let transport = ScriptedTransport([
            .json(#"{"id":2,"crew":[{"job":"Director","id":11,"name":"同名导演"}]}"#),
            .failure(.rateLimited(.tmdb)), .json(#"{"id":1,"crew":[]}"#)
        ])
        let catalog = MediaCatalogService(keychain: MemoryKeychain([.tmdb: "fake"]), tmdb: TMDBClient(transport: transport))
        let backfill = MovieMetadataBackfill()
        let task = try #require(backfill.startDirectors(store: store, catalog: catalog))
        #expect(backfill.startSeries(store: store, catalog: catalog) == nil)
        await task.value
        #expect(newer.movieDirectors == [director(11)] && older.needsLookup(.directors))
        #expect(backfill.messages[.directors]?.contains("频繁") == true)
        await backfill.startDirectors(store: store, catalog: catalog)?.value
        #expect(older.movieDirectors == [] && !older.needsLookup(.directors))
        #expect(newer.latestViewingID == event && newer.seriesLookup == series && newer.watchStatus == .watching)
        #expect(newer.myRating == 8 && newer.shortReview == "保留")
        #expect(await transport.requests.map { $0.url?.path } == ["/3/movie/2/credits", "/3/movie/1/credits", "/3/movie/1/credits"])
        let reopened = try PersistenceController.makeContainer(in: directory)
        #expect(try RecordStore(context: reopened.mainContext).recordsNewestFirst().allSatisfy { !$0.needsLookup(.directors) })
    }

    @Test("头像使用人物图尺寸，备份恢复可离线浏览并保留共享引用")
    func cachesDirectorPortrait() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try PersistenceController.makeContainer(in: dir.appendingPathComponent("source"))
        let person = director(11, profile: "/portrait.jpg")
        let first = ViewingRecord(tmdbID: 1, mediaType: .movie, title: "第一部", movieDirectors: [person])
        let second = ViewingRecord(tmdbID: 2, mediaType: .movie, title: "第二部", movieDirectors: [person])
        let store = RecordStore(context: source.mainContext)
        try store.insert(first)
        try store.insert(second)
        let path = try #require(person.profilePath)
        let transport = PosterTransport([.success(HTTPResponse(data: PosterFixtures.png, statusCode: 200))])
        let cache = PosterCache(directory: dir.appendingPathComponent("images"), transport: transport)
        let portrait = try await cache.loadProfile(path: path)
        #expect(portrait.filename == person.profileFilename && portrait.filename != PosterCache.filename(for: path))
        #expect(await transport.requests.first?.url?.path == "/t/p/h632/portrait.jpg")
        let archive = try await LibraryBackup.snapshot(context: source.mainContext, cache: cache)
        #expect(archive.posters == [portrait.filename: PosterFixtures.png])
        let encoded = try JSONEncoder().encode(archive)
        let restored = try JSONDecoder().decode(LibraryBackup.self, from: encoded)
        let target = try PersistenceController.makeContainer(in: dir.appendingPathComponent("target"))
        let offline = PosterTransport([])
        let targetCache = PosterCache(directory: dir.appendingPathComponent("restoredImages"), transport: offline)
        #expect(try await restored.restore(context: target.mainContext, cache: targetCache) == 2)
        let targetStore = RecordStore(context: target.mainContext)
        #expect(try targetStore.recordsNewestFirst().allSatisfy { $0.movieDirectors == [person] })
        let cleanup = PosterCleanupCoordinator(cache: targetCache)
        try targetStore.delete(recordID: first.id)
        cleanup.requestCleanup(store: targetStore)
        await cleanup.cleanupTask?.value
        #expect(try await targetCache.loadProfile(path: path).data == PosterFixtures.png)
        #expect(await offline.requests.isEmpty)
        try targetStore.delete(recordID: second.id)
        cleanup.requestCleanup(store: targetStore)
        await cleanup.cleanupTask?.value
        await #expect(throws: PosterCacheError.localFileUnavailable) { try await targetCache.readData(filename: portrait.filename) }
    }
}
