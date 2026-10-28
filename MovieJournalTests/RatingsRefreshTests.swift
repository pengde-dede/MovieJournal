import Foundation
import SwiftData
import Testing
@testable import MovieJournal

@Suite("旧记录刷新补充评分")
@MainActor
struct RatingsRefreshTests {
    @Test("电影与剧集旧记录可补分，重开后评分保留且个人信息和资料不变", arguments: [MediaType.movie, .tv])
    func refreshPersistsAndPreservesSnapshot(type: MediaType) async throws {
        let fixture = try database(type: type)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let record = fixture.record
        let id = record.id
        let createdAt = record.createdAt
        let updatedAt = record.updatedAt
        let personal = RecordDraft(record: record)
        var expectedMetadata = MediaDetails(record: record)
        expectedMetadata.imdbRating = 9.2
        expectedMetadata.rottenTomatoesRating = 89
        let catalog = RefreshCatalog(.loaded(PlatformRatings(imdb: 9.2, rottenTomatoes: 89)))
        let model = RecordDetailViewModel()
        let task = model.refreshRatings(recordID: id, imdbID: record.imdbID, catalog: catalog, store: fixture.store)
        #expect(model.isRefreshingRatings)
        await task.value
        #expect(!model.isRefreshingRatings && !model.ratingsRefreshFailed)
        #expect(model.ratingsMessage?.contains("保存到本机") == true)
        #expect(await catalog.requestedIDs == [record.imdbID])
        let reopened = try PersistenceController.makeContainer(in: fixture.directory)
        let records = try RecordStore(context: reopened.mainContext).recordsNewestFirst()
        #expect(records.count == 1)
        let saved = try #require(records.first)
        #expect(saved.id == id && saved.createdAt == createdAt && saved.updatedAt == updatedAt)
        #expect(saved.myRating == personal.myRating && saved.shortReview == personal.shortReview)
        #expect(saved.watchedOn == personal.watchedOn && saved.watchedSeason == personal.watchedSeason)
        #expect(saved.posterFilename == personal.posterFilename)
        #expect(MediaDetails(record: saved) == expectedMetadata)
    }

    @Test("某项或全部评分缺失时保留已存评分", arguments: [
        PlatformRatings(imdb: 8.5, rottenTomatoes: nil),
        PlatformRatings(imdb: nil, rottenTomatoes: 95),
        PlatformRatings(imdb: nil, rottenTomatoes: nil)
    ])
    func missingRatingsDoNotEraseValues(ratings: PlatformRatings) async throws {
        let fixture = try database()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try fixture.store.updateSupplementalRatings(PlatformRatings(imdb: 7.1, rottenTomatoes: 45),
            recordID: fixture.record.id, expectedIMDbID: "tt0111161")
        let model = RecordDetailViewModel()
        await model.refreshRatings(recordID: fixture.record.id, imdbID: fixture.record.imdbID,
            catalog: RefreshCatalog(.loaded(ratings)), store: fixture.store).value
        #expect(fixture.record.imdbRating == (ratings.imdb ?? 7.1))
        #expect(fixture.record.rottenTomatoesRating == (ratings.rottenTomatoes ?? 45))
        #expect(model.ratingsMessage?.contains("原值保留") == true)
        #expect(!model.ratingsRefreshFailed)
    }

    @Test("未配置、无效 Key、断网及额度耗尽不改评分且给出中文提示", arguments: [0, 1, 2, 3])
    func serviceFailuresPreserveSavedValues(scenario: Int) async throws {
        let fixture = try database()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try fixture.store.updateSupplementalRatings(PlatformRatings(imdb: 7.1, rottenTomatoes: 45),
            recordID: fixture.record.id, expectedIMDbID: "tt0111161")
        let replies: [StubReply]
        let expectedMessage: String
        switch scenario {
        case 0: replies = []; expectedMessage = "填写并保存 OMDb Key"
        case 1: replies = [.json(#"{"Response":"False","Error":"Invalid API key!"}"#)]; expectedMessage = "无效"
        case 2: replies = [.failure(.networkUnavailable)]; expectedMessage = "网络连接失败"
        default: replies = [.json(#"{"Response":"False","Error":"Request limit reached!"}"#)]; expectedMessage = "请求次数"
        }
        let transport = ScriptedTransport(replies)
        let catalog = MediaCatalogService(keychain: MemoryKeychain(scenario == 0 ? [:] : [.omdb: "fake-omdb"]),
            tmdb: TMDBClient(transport: transport), omdb: OMDbClient(transport: transport))
        let model = RecordDetailViewModel()
        await model.refreshRatings(recordID: fixture.record.id, imdbID: fixture.record.imdbID, catalog: catalog, store: fixture.store).value
        #expect(model.ratingsRefreshFailed && !model.isRefreshingRatings)
        #expect(model.ratingsMessage?.contains(expectedMessage) == true)
        #expect(fixture.record.imdbRating == 7.1 && fixture.record.rottenTomatoesRating == 45)
        #expect(!fixture.container.mainContext.hasChanges)
        let requests = await transport.requests
        #expect(requests.count == (scenario == 0 ? 0 : 1))
        #expect(requests.allSatisfy { $0.url?.host == "www.omdbapi.com" })
    }

    @Test("缺少 IMDb 编号时直接解释原因，不发请求", arguments: [nil, "", "  "] as [String?])
    func missingIMDbIDDoesNotRequest(identifier: String?) async throws {
        let fixture = try database()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let catalog = RefreshCatalog(.noIMDbID)
        let model = RecordDetailViewModel()
        await model.refreshRatings(recordID: fixture.record.id, imdbID: identifier, catalog: catalog, store: fixture.store).value
        #expect(model.ratingsMessage?.contains("没有 IMDb 编号") == true)
        #expect(!model.isRefreshingRatings)
        #expect(await catalog.requestedIDs.isEmpty)
    }

    @Test("连续点击仅发出一次请求，刷新完成后可再次使用")
    func repeatedClickDoesNotDuplicateRequest() async throws {
        let fixture = try database()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let catalog = RefreshCatalog(.loaded(PlatformRatings(imdb: 8.8, rottenTomatoes: 88)), holdFirst: true)
        let model = RecordDetailViewModel()
        let first = model.refreshRatings(recordID: fixture.record.id, imdbID: fixture.record.imdbID, catalog: catalog, store: fixture.store)
        await catalog.waitForRequest()
        let repeated = model.refreshRatings(recordID: fixture.record.id, imdbID: fixture.record.imdbID, catalog: catalog, store: fixture.store)
        await catalog.finishFirst()
        await first.value
        await repeated.value
        #expect(await catalog.requestedIDs.count == 1)
        await model.refreshRatings(recordID: fixture.record.id, imdbID: fixture.record.imdbID, catalog: catalog, store: fixture.store).value
        #expect(await catalog.requestedIDs.count == 2)
        #expect(fixture.record.imdbRating == 8.8)
    }

    @Test("离开详情后旧请求不写库，再刷新不会被旧响应覆盖")
    func cancelledResponseCannotOverwriteRetry() async throws {
        let fixture = try database()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let oldCatalog = RefreshCatalog(.loaded(PlatformRatings(imdb: 1, rottenTomatoes: 10)), holdFirst: true)
        let newCatalog = RefreshCatalog(.loaded(PlatformRatings(imdb: 9, rottenTomatoes: 90)))
        let model = RecordDetailViewModel()
        let old = model.refreshRatings(recordID: fixture.record.id, imdbID: fixture.record.imdbID, catalog: oldCatalog, store: fixture.store)
        await oldCatalog.waitForRequest()
        model.cancelRatingRefresh()
        #expect(!model.isRefreshingRatings && model.ratingsMessage == nil)
        await model.refreshRatings(recordID: fixture.record.id, imdbID: fixture.record.imdbID, catalog: newCatalog, store: fixture.store).value
        let message = model.ratingsMessage
        await oldCatalog.finishFirst()
        await old.value
        #expect(fixture.record.imdbRating == 9 && fixture.record.rottenTomatoesRating == 90)
        #expect(model.ratingsMessage == message && !model.isRefreshingRatings)
    }

    @Test("刷新期间修改个人信息和海报引用，结果只更新评分")
    func concurrentPersonalEditIsPreserved() async throws {
        let fixture = try database(type: .tv)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let catalog = RefreshCatalog(.loaded(PlatformRatings(imdb: 9, rottenTomatoes: 90)), holdFirst: true)
        let model = RecordDetailViewModel()
        let task = model.refreshRatings(recordID: fixture.record.id, imdbID: fixture.record.imdbID, catalog: catalog, store: fixture.store)
        await catalog.waitForRequest()
        let watchedOn = Date(timeIntervalSince1970: 300)
        try fixture.store.updatePersonalInformation(recordID: fixture.record.id, watchedOn: watchedOn, myRating: 10, shortReview: "另一窗口修改", watchedSeason: 4)
        try fixture.store.setPosterFilename("repaired.image", recordID: fixture.record.id, expectedPath: fixture.record.posterPath)
        let personalUpdatedAt = fixture.record.updatedAt
        await catalog.finishFirst()
        await task.value
        #expect(fixture.record.myRating == 10 && fixture.record.shortReview == "另一窗口修改")
        #expect(fixture.record.watchedSeason == 4 && fixture.record.watchedOn == watchedOn)
        #expect(fixture.record.posterFilename == "repaired.image" && fixture.record.updatedAt == personalUpdatedAt)
        #expect(fixture.record.imdbRating == 9 && fixture.record.rottenTomatoesRating == 90)
    }

    @Test("旧记录删除后同一作品重新添加，迟到的评分不能写入新记录")
    func deletedRecordCannotBeResurrected() async throws {
        let fixture = try database()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let identifier = fixture.record.id
        let imdbID = fixture.record.imdbID
        let catalog = RefreshCatalog(.loaded(PlatformRatings(imdb: 9, rottenTomatoes: 90)), holdFirst: true)
        let model = RecordDetailViewModel()
        let task = model.refreshRatings(recordID: identifier, imdbID: imdbID, catalog: catalog, store: fixture.store)
        await catalog.waitForRequest()
        try fixture.store.delete(recordID: identifier)
        let replacement = ViewingRecord(tmdbID: 278, mediaType: .movie, title: "重新添加", imdbID: imdbID, myRating: 6)
        try fixture.store.insert(replacement)
        await catalog.finishFirst()
        await task.value
        #expect(model.ratingsRefreshFailed && model.ratingsMessage?.contains("其他窗口删除") == true)
        #expect(try fixture.store.recordsNewestFirst().map(\.id) == [replacement.id])
        #expect(replacement.imdbRating == nil && replacement.myRating == 6)
    }

    @Test("IMDb 编号改变后，旧请求不能把另一部作品的评分写入记录")
    func changedIMDbIDRejectsOldResult() async throws {
        let fixture = try database()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let catalog = RefreshCatalog(.loaded(PlatformRatings(imdb: 9, rottenTomatoes: 90)), holdFirst: true)
        let model = RecordDetailViewModel()
        let task = model.refreshRatings(recordID: fixture.record.id, imdbID: fixture.record.imdbID, catalog: catalog, store: fixture.store)
        await catalog.waitForRequest()
        fixture.record.imdbID = "tt0903747"
        try fixture.container.mainContext.save()
        await catalog.finishFirst()
        await task.value
        #expect(model.ratingsRefreshFailed && model.ratingsMessage?.contains("IMDb 编号已改变") == true)
        #expect(fixture.record.imdbRating == nil && fixture.record.rottenTomatoesRating == nil)
    }

    @Test("保存失败时回滚评分并可重试，输入和个人信息不受影响")
    func failedSaveRollsBackAndRetryWorks() async throws {
        let fixture = try database()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let store = RecordStore(context: fixture.container.mainContext) { throw RefreshWriteFailure.unavailable }
        let catalog = RefreshCatalog(.loaded(PlatformRatings(imdb: 9, rottenTomatoes: 90)))
        let model = RecordDetailViewModel()
        await model.refreshRatings(recordID: fixture.record.id, imdbID: fixture.record.imdbID, catalog: catalog, store: store).value
        #expect(model.ratingsRefreshFailed && model.ratingsMessage?.contains("未能更新") == true)
        #expect(fixture.record.imdbRating == nil && fixture.record.rottenTomatoesRating == nil)
        #expect(fixture.record.myRating == 8 && fixture.record.shortReview == "原短评")
        #expect(!fixture.container.mainContext.hasChanges)
        await model.refreshRatings(recordID: fixture.record.id, imdbID: fixture.record.imdbID, catalog: catalog, store: fixture.store).value
        #expect(!model.ratingsRefreshFailed && fixture.record.imdbRating == 9)
    }

    @Test("断网失败后恢复可直接重试，不必重新添加作品")
    func networkRetryUpdatesExistingRecord() async throws {
        let fixture = try database()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let transport = ScriptedTransport([.failure(.networkUnavailable), .json(#"{"Response":"True","imdbRating":"9.3","Ratings":[{"Source":"Rotten Tomatoes","Value":"89%"}]}"#)])
        let catalog = MediaCatalogService(keychain: MemoryKeychain([.omdb: "fake-omdb"]), omdb: OMDbClient(transport: transport))
        let model = RecordDetailViewModel()
        await model.refreshRatings(recordID: fixture.record.id, imdbID: fixture.record.imdbID, catalog: catalog, store: fixture.store).value
        #expect(model.ratingsRefreshFailed)
        await model.refreshRatings(recordID: fixture.record.id, imdbID: fixture.record.imdbID, catalog: catalog, store: fixture.store).value
        #expect(!model.ratingsRefreshFailed && fixture.record.imdbRating == 9.3 && fixture.record.rottenTomatoesRating == 89)
        #expect(try fixture.store.recordsNewestFirst().count == 1)
        #expect(await transport.requests.count == 2)
    }

    private func database(type: MediaType = .movie) throws -> (directory: URL, container: ModelContainer, store: RecordStore, record: ViewingRecord) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MovieJournalRefreshTests-\(UUID().uuidString)", isDirectory: true)
        let container = try PersistenceController.makeContainer(in: directory)
        let store = RecordStore(context: container.mainContext)
        let details = Fixtures.details(type == .movie ? Fixtures.movie : Fixtures.series)
        let record = ViewingRecord(tmdbID: details.tmdbID, mediaType: type, title: details.title,
            originalTitle: details.originalTitle, releaseYear: details.releaseYear, genres: details.genres,
            overview: details.overview, creatorNames: details.creatorNames, castNames: details.castNames,
            imdbID: details.imdbID, tmdbRating: details.tmdbRating, posterPath: details.posterPath,
            posterFilename: "original.image", watchedOn: Date(timeIntervalSince1970: 150), myRating: 8,
            shortReview: "原短评", watchedSeason: type == .tv ? 2 : nil, createdAt: Date(timeIntervalSince1970: 100), metadataFetchedAt: details.fetchedAt)
        try store.insert(record)
        return (directory, container, store, record)
    }
}

private enum RefreshWriteFailure: Error { case unavailable }

private actor RefreshCatalog: MediaCatalogServing {
    let result: SupplementalRatingsResult
    let holdFirst: Bool
    private(set) var requestedIDs: [String?] = []
    private var continuation: CheckedContinuation<SupplementalRatingsResult, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    init(_ result: SupplementalRatingsResult, holdFirst: Bool = false) { self.result = result; self.holdFirst = holdFirst }
    func search(title: String) async throws -> [MediaSearchResult] { throw APIError.invalidResponse }
    func details(for candidate: MediaSearchResult) async throws -> MediaDetails { throw APIError.invalidResponse }
    func supplementalRatings(imdbID: String?) async throws -> SupplementalRatingsResult {
        requestedIDs.append(imdbID)
        if holdFirst, requestedIDs.count == 1 {
            return await withCheckedContinuation { continuation = $0; waiter?.resume(); waiter = nil }
        }
        return result
    }
    func waitForRequest() async {
        if continuation != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func finishFirst() { continuation?.resume(returning: result); continuation = nil }
}
