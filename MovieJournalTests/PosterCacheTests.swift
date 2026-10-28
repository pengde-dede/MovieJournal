import Foundation
import Testing
@testable import MovieJournal

@Suite("海报文件缓存")
struct PosterCacheTests {
    @Test("缓存写入磁盘后，新实例在断网下可按路径或文件名读取")
    func diskCacheSurvivesRelaunchOffline() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let online = PosterTransport([.success(HTTPResponse(data: PosterFixtures.png, statusCode: 200))])
        let first = try await PosterCache(directory: directory, transport: online).load(path: "/poster.jpg", filename: nil)
        #expect(try Data(contentsOf: directory.appendingPathComponent(first.filename)) == PosterFixtures.png)
        #expect(!first.filename.contains("/"))
        let offline = PosterTransport([])
        let reopened = PosterCache(directory: directory, transport: offline)
        let byPath = try await reopened.load(path: "/poster.jpg", filename: nil)
        let byFilename = try await reopened.load(path: nil, filename: first.filename)
        #expect(byPath.data == first.data)
        #expect(byFilename.data == first.data)
        #expect(await offline.requests.isEmpty)
        let requests = await online.requests
        #expect(requests.count == 1)
        #expect(requests.first?.url?.scheme == "https")
        #expect(requests.first?.url?.host == "image.tmdb.org")
        #expect(requests.first?.url?.path == "/t/p/w500/poster.jpg")
    }

    @Test("共用同一海报下载，一个调用者取消后仍可供其他调用者使用")
    func sharedDownloadSurvivesOneCancelledCaller() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = HeldImageTransport()
        let cache = PosterCache(directory: directory, transport: transport)
        let first = Task { try await cache.load(path: "/shared.jpg", filename: nil) }
        await transport.waitUntilRequested()
        let second = Task { try await cache.load(path: "/shared.jpg", filename: nil) }
        first.cancel()
        await transport.finish()
        let one = try await first.value
        let two = try await second.value
        #expect(one.filename == two.filename)
        #expect(two.data == PosterFixtures.png)
        #expect(await transport.requestCount == 1)
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent(two.filename).path))
    }

    @Test("损坏的本地图片可以重新下载并原子替换")
    func corruptFileIsReplaced() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let filename = try #require(PosterCache.filename(for: "/broken.jpg"))
        try Data("damaged".utf8).write(to: directory.appendingPathComponent(filename))
        let transport = PosterTransport([.success(HTTPResponse(data: PosterFixtures.png, statusCode: 200))])
        let poster = try await PosterCache(directory: directory, transport: transport).load(path: "/broken.jpg", filename: filename)
        #expect(poster.data == PosterFixtures.png)
        #expect(try Data(contentsOf: directory.appendingPathComponent(filename)) == PosterFixtures.png)
        #expect(await transport.requests.count == 1)
    }

    @Test("错误状态码或非图片内容不写入缓存", arguments: [200, 404])
    func invalidDownloadDoesNotCreateFile(status: Int) async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = PosterTransport([.success(HTTPResponse(data: Data("not an image".utf8), statusCode: status))])
        let cache = PosterCache(directory: directory, transport: transport)
        let expected: PosterCacheError = status == 200 ? .invalidImage : .downloadFailed
        await #expect(throws: expected) { try await cache.load(path: "/invalid.jpg", filename: nil) }
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test("目录无法写入时提供存储错误，不把它当成缓存成功")
    func unwritableLocationReportsFailure() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("occupied".utf8).write(to: directory)
        let transport = PosterTransport([.success(HTTPResponse(data: PosterFixtures.png, statusCode: 200))])
        let cache = PosterCache(directory: directory, transport: transport)
        await #expect(throws: PosterCacheError.storageUnavailable) { try await cache.load(path: "/poster.jpg", filename: nil) }
        #expect(try String(contentsOf: directory, encoding: .utf8) == "occupied")
    }

    @Test("不接受越界文件名；缺少海报地址时也不发网络请求")
    func unsafeFilenameAndMissingPosterAreHandled() async throws {
        let directory = temporaryDirectory()
        let transport = PosterTransport([])
        let cache = PosterCache(directory: directory, transport: transport)
        await #expect(throws: PosterCacheError.noPoster) { try await cache.load(path: nil, filename: "../outside.image") }
        await #expect(throws: PosterCacheError.noPoster) { try await cache.load(path: nil, filename: nil) }
        #expect(await transport.requests.isEmpty)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("MovieJournalPosterTests-\(UUID().uuidString)", isDirectory: true)
    }
}

private actor HeldImageTransport: HTTPTransport {
    private(set) var requestCount = 0
    private var continuation: CheckedContinuation<HTTPResponse, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    func send(_ request: URLRequest) async throws -> HTTPResponse {
        requestCount += 1
        return await withCheckedContinuation {
            continuation = $0
            waiter?.resume(); waiter = nil
        }
    }
    func waitUntilRequested() async {
        if continuation != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func finish() {
        continuation?.resume(returning: HTTPResponse(data: PosterFixtures.png, statusCode: 200))
        continuation = nil
    }
}
