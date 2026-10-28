import Foundation
import SwiftData
import Testing
@testable import MovieJournal

@Suite("添加、保存与请求顺序")
@MainActor
struct AddRecordTests {
    @Test("旧搜索晚返回时不覆盖新结果")
    func oldSearchDoesNotOverwriteNewResults() async throws {
        let fixture = try storeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let catalog = ControlledCatalog()
        let model = AddRecordViewModel(catalog: catalog, store: fixture.store)
        model.query = "旧搜索"
        let old = model.search()
        await catalog.waitForSearch()
        model.query = "新搜索"
        await model.search().value
        await catalog.finishSearch()
        await old.value
        #expect(model.results == [Fixtures.series])
        #expect(!model.isSearching)
    }

    @Test("先前选中作品的慢详情不会覆盖后来选择")
    func oldDetailsDoNotOverwriteNewSelection() async throws {
        let fixture = try storeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let catalog = ControlledCatalog(holdMovieDetails: true)
        let model = AddRecordViewModel(catalog: catalog, store: fixture.store)
        let old = model.select(Fixtures.movie)
        await catalog.waitForDetails()
        await model.select(Fixtures.series).value
        await catalog.finishDetails()
        await old.value
        await model.supplementalTask?.value
        #expect(model.draft?.details.tmdbID == Fixtures.series.tmdbID)
        #expect(model.selectedResult == Fixtures.series)
    }

    @Test("OMDb 仍在加载时可以保存，晚到评分不修改已保存快照")
    func supplementalLoadingDoesNotBlockSave() async throws {
        let fixture = try storeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let catalog = ControlledCatalog(holdSupplemental: true)
        let model = AddRecordViewModel(catalog: catalog, store: fixture.store)
        await model.select(Fixtures.movie).value
        await catalog.waitForSupplemental()
        #expect(model.isLoadingSupplemental)
        model.draft?.myRating = 9
        model.draft?.shortReview = "我的短评"
        let id = model.saveRecord()
        await catalog.finishSupplemental()
        await model.supplementalTask?.value
        #expect(id != nil)
        let records = try fixture.store.recordsNewestFirst()
        let record = try #require(records.first)
        #expect(record.myRating == 9)
        #expect(record.shortReview == "我的短评")
        #expect(record.imdbRating == nil)
        #expect(record.rottenTomatoesRating == nil)
    }

    @Test("重复选择返回已有记录编号，不查询详情或覆盖个人信息")
    func duplicateOffersExistingRecord() async throws {
        let fixture = try storeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let original = ViewingRecord(tmdbID: 278, mediaType: .movie, title: "原记录", myRating: 10, shortReview: "保留")
        try fixture.store.insert(original)
        let catalog = ControlledCatalog()
        let model = AddRecordViewModel(catalog: catalog, store: fixture.store)
        await model.select(Fixtures.movie).value
        #expect(model.duplicateRecordID == original.id)
        #expect(model.draft == nil)
        #expect(await catalog.detailsCount == 0)
        #expect(original.myRating == 10)
        #expect(original.shortReview == "保留")
    }

    @Test("取消添加不写库；评分与季数未填写时不能生成记录")
    func cancellingDoesNotPersistDraft() async throws {
        let fixture = try storeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let model = AddRecordViewModel(catalog: ControlledCatalog(), store: fixture.store)
        await model.select(Fixtures.series).value
        await model.supplementalTask?.value
        #expect(model.draft?.validationMessage != nil)
        model.draft?.myRating = 8
        #expect(model.draft?.validationMessage != nil)
        model.draft?.watchedSeason = 2
        #expect(model.draft?.validationMessage == nil)
        model.cancelPendingWork()
        #expect(try fixture.store.recordsNewestFirst().isEmpty)
    }

    @Test("保存剧集后重新打开数据库仍保留资料、个人信息和进度")
    func savedSeriesSurvivesReopening() async throws {
        let fixture = try storeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let model = AddRecordViewModel(catalog: ControlledCatalog(), store: fixture.store)
        await model.select(Fixtures.series).value
        await model.supplementalTask?.value
        model.draft?.myRating = 8
        model.draft?.watchedSeason = 3
        model.draft?.shortReview = "看到第三季"
        #expect(model.saveRecord() != nil)
        let reopened = try PersistenceController.makeContainer(in: fixture.directory)
        let records = try RecordStore(context: reopened.mainContext).recordsNewestFirst()
        let record = try #require(records.first)
        #expect(record.mediaType == .tv)
        #expect(record.title == "绝命毒师")
        #expect(record.myRating == 8)
        #expect(record.watchedSeason == 3)
        #expect(record.shortReview == "看到第三季")
        #expect(record.posterPath == Fixtures.series.posterPath)
    }

    @Test("OMDb 返回无效 Key 时，主资料和个人信息仍可完整保存")
    func supplementalFailureDoesNotBlockSave() async throws {
        let fixture = try storeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let transport = ScriptedTransport([
            .json(try Fixtures.movieJSON()),
            .json(#"{"Response":"False","Error":"Invalid API key!"}"#)
        ])
        let catalog = MediaCatalogService(
            keychain: MemoryKeychain([.tmdb: "fake-tmdb", .omdb: "fake-invalid"]),
            tmdb: TMDBClient(transport: transport), omdb: OMDbClient(transport: transport)
        )
        let model = AddRecordViewModel(catalog: catalog, store: fixture.store)
        await model.select(Fixtures.movie).value
        await model.supplementalTask?.value
        #expect(model.draft != nil)
        #expect(model.supplementalMessage != nil)
        model.draft?.myRating = 9
        model.draft?.shortReview = "补充评分失败也保留"
        #expect(model.saveRecord() != nil)
        let records = try fixture.store.recordsNewestFirst()
        let record = try #require(records.first)
        #expect(record.title == "肖申克的救赎")
        #expect(record.creatorNames == ["Frank Darabont"])
        #expect(record.tmdbRating == 8.7)
        #expect(record.imdbRating == nil)
        #expect(record.rottenTomatoesRating == nil)
        #expect(record.myRating == 9)
        #expect(record.shortReview == "补充评分失败也保留")
    }

    private func storeFixture() throws -> (directory: URL, container: ModelContainer, store: RecordStore) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MovieJournalAddTests-\(UUID().uuidString)", isDirectory: true)
        let container = try PersistenceController.makeContainer(in: directory)
        return (directory, container, RecordStore(context: container.mainContext))
    }
}

private actor ControlledCatalog: MediaCatalogServing {
    private let holdMovieDetails: Bool
    private let holdSupplemental: Bool
    private(set) var detailsCount = 0
    private var searchContinuation: CheckedContinuation<[MediaSearchResult], Never>?
    private var detailsContinuation: CheckedContinuation<MediaDetails, Never>?
    private var supplementalContinuation: CheckedContinuation<SupplementalRatingsResult, Never>?
    private var searchWaiter: CheckedContinuation<Void, Never>?
    private var detailsWaiter: CheckedContinuation<Void, Never>?
    private var supplementalWaiter: CheckedContinuation<Void, Never>?
    init(holdMovieDetails: Bool = false, holdSupplemental: Bool = false) {
        self.holdMovieDetails = holdMovieDetails
        self.holdSupplemental = holdSupplemental
    }
    func search(title: String) async throws -> [MediaSearchResult] {
        if title != "旧搜索" { return [Fixtures.series] }
        return await withCheckedContinuation {
            searchContinuation = $0; searchWaiter?.resume(); searchWaiter = nil
        }
    }
    func details(for candidate: MediaSearchResult) async throws -> MediaDetails {
        detailsCount += 1
        if !holdMovieDetails || candidate.mediaType != .movie { return Fixtures.details(candidate) }
        return await withCheckedContinuation {
            detailsContinuation = $0; detailsWaiter?.resume(); detailsWaiter = nil
        }
    }
    func supplementalRatings(imdbID: String?) async throws -> SupplementalRatingsResult {
        if !holdSupplemental { return .notConfigured }
        return await withCheckedContinuation {
            supplementalContinuation = $0; supplementalWaiter?.resume(); supplementalWaiter = nil
        }
    }
    func waitForSearch() async {
        if searchContinuation != nil { return }
        await withCheckedContinuation { searchWaiter = $0 }
    }
    func waitForDetails() async {
        if detailsContinuation != nil { return }
        await withCheckedContinuation { detailsWaiter = $0 }
    }
    func waitForSupplemental() async {
        if supplementalContinuation != nil { return }
        await withCheckedContinuation { supplementalWaiter = $0 }
    }
    func finishSearch() { searchContinuation?.resume(returning: [Fixtures.movie]); searchContinuation = nil }
    func finishDetails() { detailsContinuation?.resume(returning: Fixtures.details()); detailsContinuation = nil }
    func finishSupplemental() { supplementalContinuation?.resume(returning: .loaded(PlatformRatings(imdb: 9.3, rottenTomatoes: 89))); supplementalContinuation = nil }
}
