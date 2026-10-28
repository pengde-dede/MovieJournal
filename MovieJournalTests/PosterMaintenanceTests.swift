import Foundation
import SwiftData
import Testing
@testable import MovieJournal

@Suite("海报缓存职责与补存范围")
@MainActor
struct PosterMaintenanceTests {
    @Test("搜索候选使用 w185，浏览二十条候选不创建持久海报文件")
    func candidatesDoNotCreatePersistentFiles() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let posterDirectory = root.appendingPathComponent("Posters", isDirectory: true)
        let transport = PosterTransport(Array(repeating: .success(HTTPResponse(data: PosterFixtures.png, statusCode: 200)), count: 20))
        let thumbnails = PosterThumbnailCache(transport: transport)
        for index in 1...20 { _ = try await thumbnails.load(path: "/candidate-\(index).jpg") }
        let requests = await transport.requests
        #expect(requests.count == 20)
        #expect(requests.allSatisfy { $0.url?.path.hasPrefix("/t/p/w185/") == true })
        #expect(!FileManager.default.fileExists(atPath: posterDirectory.path))
    }

    @Test("已存在的海报只检查文件，不解码、联网或触发统一刷新")
    func existingFilesAreNotReadByBackfill() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try PersistenceController.makeContainer(in: root)
        let store = RecordStore(context: container.mainContext)
        let filename = try #require(PosterCache.filename(for: "/existing.jpg"))
        let directory = root.appendingPathComponent("Posters", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // 非图片字节用于证明补存扫描没有读取或解码已有文件。
        let bytes = Data("existence check only".utf8)
        try bytes.write(to: directory.appendingPathComponent(filename))
        let record = ViewingRecord(tmdbID: 278, mediaType: .movie, title: "已有记录", posterPath: "/existing.jpg", posterFilename: filename, myRating: 8)
        try store.insert(record)
        let transport = PosterTransport([])
        let cache = PosterCache(directory: directory, transport: transport)
        let cleanup = PosterCleanupCoordinator(cache: cache)
        let model = LibraryViewModel()
        await model.cacheSavedPosters([SavedPosterTarget(recordID: record.id, path: record.posterPath, filename: filename)],
            cache: cache, store: store, cleanup: cleanup)
        #expect(await transport.requests.isEmpty)
        #expect(model.totalPosters == 0)
        #expect(model.posterReloadVersions.isEmpty)
        #expect(model.posterMessage == nil)
        #expect(try Data(contentsOf: directory.appendingPathComponent(filename)) == bytes)
    }

    @Test("缩略图只在当前内存缓存中复用，新实例需要重新获取")
    func thumbnailCacheIsMemoryOnly() async throws {
        let transport = PosterTransport(Array(repeating: .success(HTTPResponse(data: PosterFixtures.png, statusCode: 200)), count: 2))
        let first = PosterThumbnailCache(transport: transport)
        #expect(try await first.load(path: "/same.jpg") == PosterFixtures.png)
        #expect(try await first.load(path: "/same.jpg") == PosterFixtures.png)
        #expect(await transport.requests.count == 1)
        let reopened = PosterThumbnailCache(transport: transport)
        #expect(try await reopened.load(path: "/same.jpg") == PosterFixtures.png)
        #expect(await transport.requests.count == 2)
    }

    @Test("候选浏览后，只有选中的作品准备保存时写入一张 w500")
    func onlySelectedWorkGetsPersistentPoster() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try PersistenceController.makeContainer(in: root)
        let directory = root.appendingPathComponent("Posters", isDirectory: true)
        let previewNetwork = PosterTransport(Array(repeating: .success(HTTPResponse(data: PosterFixtures.png, statusCode: 200)), count: 20))
        let thumbnails = PosterThumbnailCache(transport: previewNetwork)
        for index in 1...20 { _ = try await thumbnails.load(path: "/candidate-\(index).jpg") }
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        let fullNetwork = PosterTransport([.success(HTTPResponse(data: PosterFixtures.png, statusCode: 200))])
        let model = AddRecordViewModel(catalog: MaintenanceCatalog(), store: RecordStore(context: container.mainContext),
            posters: PosterCache(directory: directory, transport: fullNetwork))
        await model.select(Fixtures.movie).value
        await model.posterTask?.value
        await model.supplementalTask?.value
        let filename = try #require(model.draft?.posterFilename)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == [filename])
        let requests = await fullNetwork.requests
        #expect(requests.count == 1)
        #expect(requests.first?.url?.path == "/t/p/w500/poster.jpg")
        model.draft?.myRating = 8
        #expect(model.saveRecord() != nil)
        #expect(try RecordStore(context: container.mainContext).recordsNewestFirst().first?.posterFilename == filename)
    }

    @Test("启动先修复旧文件引用再清理，查询尚未显示记录时也不会误删")
    func startupRepairsReferencesBeforeCleanup() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try PersistenceController.makeContainer(in: root)
        let store = RecordStore(context: container.mainContext)
        let directory = root.appendingPathComponent("Posters", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let kept = try #require(PosterCache.filename(for: "/legacy.jpg"))
        let orphan = try #require(PosterCache.filename(for: "/unselected.jpg"))
        for name in [kept, orphan] { try PosterFixtures.png.write(to: directory.appendingPathComponent(name)) }
        let record = ViewingRecord(tmdbID: 278, mediaType: .movie, title: "旧记录", posterPath: "/legacy.jpg", myRating: 9, shortReview: "保留")
        try store.insert(record)
        let transport = PosterTransport([])
        let cache = PosterCache(directory: directory, transport: transport)
        let cleanup = PosterCleanupCoordinator(cache: cache)
        let model = LibraryViewModel()
        // 模拟 @Query 尚未提供记录列表，维护仍应读取数据库中的真实引用。
        await model.cacheSavedPosters([], cache: cache, store: store, cleanup: cleanup)
        #expect(record.posterFilename == kept)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == [kept])
        #expect(model.posterReloadVersions.isEmpty)
        #expect(model.totalPosters == 0 && !model.isCachingPosters && !model.isPreparingLibrary)
        #expect(record.myRating == 9 && record.shortReview == "保留")
        #expect(await transport.requests.isEmpty)
    }

    @Test("只补存缺失文件，加入已缓存记录不会刷新其他卡片")
    func onlyMissingFilesLoadAndNotify() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try PersistenceController.makeContainer(in: root)
        let store = RecordStore(context: container.mainContext)
        let directory = root.appendingPathComponent("Posters", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let nameA = try #require(PosterCache.filename(for: "/a.jpg"))
        let nameB = try #require(PosterCache.filename(for: "/b.jpg"))
        let nameC = try #require(PosterCache.filename(for: "/c.jpg"))
        try PosterFixtures.png.write(to: directory.appendingPathComponent(nameA))
        let a = ViewingRecord(tmdbID: 1, mediaType: .movie, title: "已有", posterPath: "/a.jpg", posterFilename: nameA, myRating: 8)
        let b = ViewingRecord(tmdbID: 2, mediaType: .movie, title: "文件丢失", posterPath: "/b.jpg", posterFilename: nameB, myRating: 8)
        try store.insert(a); try store.insert(b)
        let transport = PosterTransport(Array(repeating: .success(HTTPResponse(data: PosterFixtures.png, statusCode: 200)), count: 2))
        let cache = PosterCache(directory: directory, transport: transport)
        let cleanup = PosterCleanupCoordinator(cache: cache)
        let model = LibraryViewModel()
        await model.cacheSavedPosters(targets([a, b]), cache: cache, store: store, cleanup: cleanup)
        #expect(model.totalPosters == 1)
        #expect(model.posterReloadVersions == [nameB: 1])
        #expect(await transport.requests.count == 1)
        try PosterFixtures.png.write(to: directory.appendingPathComponent(nameC))
        let c = ViewingRecord(tmdbID: 3, mediaType: .movie, title: "刚保存", posterPath: "/c.jpg", posterFilename: nameC, myRating: 8)
        try store.insert(c)
        await model.cacheSavedPosters(targets([a, b, c]), cache: cache, store: store, cleanup: cleanup)
        #expect(model.totalPosters == 0)
        #expect(model.posterReloadVersions == [nameB: 1])
        #expect(await transport.requests.count == 1)
        try FileManager.default.removeItem(at: directory.appendingPathComponent(nameA))
        await model.cacheSavedPosters(targets([a, b, c]), cache: cache, store: store, cleanup: cleanup)
        #expect(model.totalPosters == 1)
        #expect(model.posterReloadVersions == [nameA: 1, nameB: 1])
        #expect(await transport.requests.count == 2)
    }

    @Test("启动清理只运行一次，显式清理可复用且保留共享引用及目录外文件")
    func cleanupIsScopedAndReusable() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("Posters", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let a = try #require(PosterCache.filename(for: "/a.jpg"))
        let b = try #require(PosterCache.filename(for: "/b.jpg"))
        let orphan = try #require(PosterCache.filename(for: "/orphan.jpg"))
        for name in [a, b, orphan] { try PosterFixtures.png.write(to: directory.appendingPathComponent(name)) }
        let outside = root.appendingPathComponent("outside.txt")
        try Data("outside".utf8).write(to: outside)
        let link = directory.appendingPathComponent("link.image")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let nested = directory.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let cache = PosterCache(directory: directory, transport: PosterTransport([]))
        #expect(try await cache.cleanupAtStartup(referencedFilenames: [a, b]) == 1)
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent(a).path))
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent(b).path))
        try PosterFixtures.png.write(to: directory.appendingPathComponent(orphan))
        #expect(try await cache.cleanupAtStartup(referencedFilenames: [a, b]) == 0)
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent(orphan).path))
        // 相同文件仍被任意剩余记录引用时就保留。
        #expect(try await cache.removeUnreferencedFiles(referencedFilenames: [a, b]) == 1)
        #expect(try await cache.removeUnreferencedFiles(referencedFilenames: [b]) == 1)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(a).path))
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent(b).path))
        #expect(try String(contentsOf: outside, encoding: .utf8) == "outside")
        #expect(FileManager.default.fileExists(atPath: nested.path))
        #expect(FileManager.default.fileExists(atPath: link.path))
    }

    @Test("已有文件启动检查不显示保存进度，清理结束前不允许新添加")
    func startupGateDoesNotShowSavingIndicator() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try PersistenceController.makeContainer(in: root)
        let store = RecordStore(context: container.mainContext)
        let name = try #require(PosterCache.filename(for: "/cached.jpg"))
        let record = ViewingRecord(tmdbID: 278, mediaType: .movie, title: "已有", posterPath: "/cached.jpg", posterFilename: name, myRating: 8)
        try store.insert(record)
        let cache = GatedStartupCache(filename: name)
        let cleanup = PosterCleanupCoordinator(cache: cache)
        let model = LibraryViewModel()
        let task = Task { await model.cacheSavedPosters(targets([record]), cache: cache, store: store, cleanup: cleanup) }
        await cache.waitForCleanup()
        #expect(model.isPreparingLibrary)
        #expect(!model.isCachingPosters && model.totalPosters == 0)
        await cache.finishCleanup()
        await task.value
        #expect(!model.isPreparingLibrary && !model.isCachingPosters)
        #expect(model.posterReloadVersions.isEmpty)
        #expect(await cache.loadCount == 0)
    }

    @Test("缩略图错误不留缓存，重试仍请求 w185")
    func invalidThumbnailCanRetry() async throws {
        let transport = PosterTransport([.success(HTTPResponse(data: Data("not image".utf8), statusCode: 200)),
            .success(HTTPResponse(data: PosterFixtures.png, statusCode: 200))])
        let cache = PosterThumbnailCache(transport: transport)
        await #expect(throws: PosterCacheError.invalidImage) { try await cache.load(path: "/retry.jpg") }
        #expect(try await cache.load(path: "/retry.jpg") == PosterFixtures.png)
        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.url?.path == "/t/p/w185/retry.jpg" })
    }

    @Test("海报目录本身是符号链接时拒绝清理目录外文件")
    func symlinkedRootCannotDeleteExternalFiles() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = root.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let protectedFile = outside.appendingPathComponent("keep.txt")
        try Data("preserve".utf8).write(to: protectedFile)
        let link = root.appendingPathComponent("Posters", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let cache = PosterCache(directory: link, transport: PosterTransport([]))
        await #expect(throws: PosterCacheError.cleanupFailed) {
            try await cache.removeUnreferencedFiles(referencedFilenames: [])
        }
        #expect(try String(contentsOf: protectedFile, encoding: .utf8) == "preserve")
    }

    private func targets(_ records: [ViewingRecord]) -> [SavedPosterTarget] {
        records.map { SavedPosterTarget(recordID: $0.id, path: $0.posterPath, filename: $0.posterFilename) }
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("MovieJournalPosterMaintenanceTests-\(UUID().uuidString)", isDirectory: true)
    }
}

private nonisolated struct MaintenanceCatalog: MediaCatalogServing {
    func search(title: String) async throws -> [MediaSearchResult] { [Fixtures.movie, Fixtures.series] }
    func details(for candidate: MediaSearchResult) async throws -> MediaDetails { Fixtures.details(candidate) }
    func supplementalRatings(imdbID: String?) async throws -> SupplementalRatingsResult { .notConfigured }
}

private actor GatedStartupCache: PosterFileManaging {
    let filename: String
    private(set) var loadCount = 0
    private var continuation: CheckedContinuation<Void, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    init(filename: String) { self.filename = filename }
    func existingFilename(path: String?, filename: String?) -> String? { self.filename }
    func readData(filename: String) throws -> Data { PosterFixtures.png }
    func load(path: String?, filename: String?) throws -> CachedPoster {
        loadCount += 1
        return CachedPoster(data: PosterFixtures.png, filename: self.filename)
    }
    func cleanupAtStartup(referencedFilenames: Set<String>) async throws -> Int {
        await withCheckedContinuation { continuation = $0; waiter?.resume(); waiter = nil }
        return 0
    }
    func removeUnreferencedFiles(referencedFilenames: Set<String>) throws -> Int { 0 }
    func waitForCleanup() async {
        if continuation != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func finishCleanup() { continuation?.resume(); continuation = nil }
}
