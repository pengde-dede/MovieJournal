import Foundation

nonisolated protocol PosterThumbnailLoading: Sendable {
    func load(path: String?) async throws -> Data
}

// 搜索候选独立使用内存缓存，没有目录或文件写入依赖。
actor PosterThumbnailCache: PosterThumbnailLoading {
    static let shared = PosterThumbnailCache()
    private let transport: any HTTPTransport
    private let images = NSCache<NSURL, NSData>()
    private var inFlight: [URL: Task<Data, Error>] = [:]

    init(transport: any HTTPTransport = HTTPClient()) {
        self.transport = transport
        images.countLimit = 80
        images.totalCostLimit = 8 * 1024 * 1024
    }

    func load(path: String?) async throws -> Data {
        try Task.checkCancellation()
        guard let url = TMDBImageURL.poster(path, small: true) else { throw PosterCacheError.noPoster }
        if let data = images.object(forKey: url as NSURL) { return data as Data }
        if let task = inFlight[url] { return try await task.value }
        let task = Task { try await download(url) }
        inFlight[url] = task
        defer { inFlight[url] = nil }
        return try await task.value
    }

    private func download(_ url: URL) async throws -> Data {
        let response = try await transport.send(URLRequest(url: url))
        guard (200..<300).contains(response.statusCode) else { throw PosterCacheError.downloadFailed }
        guard PosterImageData.isValid(response.data) else { throw PosterCacheError.invalidImage }
        images.setObject(response.data as NSData, forKey: url as NSURL, cost: response.data.count)
        return response.data
    }
}
