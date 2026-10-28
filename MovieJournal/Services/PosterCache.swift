import CryptoKit
import Foundation
import ImageIO

nonisolated struct CachedPoster: Sendable {
    let data: Data
    let filename: String
}

nonisolated protocol PosterCaching: Sendable {
    func load(path: String?, filename: String?) async throws -> CachedPoster
}

nonisolated enum PosterCacheError: LocalizedError, Equatable, Sendable {
    case noPoster
    case invalidImage
    case downloadFailed
    case storageUnavailable

    var errorDescription: String? {
        switch self {
        case .noPoster: "这部作品没有可用的海报。"
        case .invalidImage: "下载的海报无法识别，请稍后重试。"
        case .downloadFailed: "海报暂时无法下载，请稍后重试。"
        case .storageUnavailable: "海报无法保存到本机，请检查可用空间和文件访问权限。"
        }
    }
}

actor PosterCache: PosterCaching {
    static let shared = PosterCache()
    private let directory: URL?
    private let transport: any HTTPTransport
    private var inFlight: [String: Task<CachedPoster, Error>] = [:]

    init(directory: URL? = nil, transport: any HTTPTransport = HTTPClient()) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("MovieJournal/Posters", isDirectory: true)
        self.transport = transport
    }

    func load(path: String?, filename: String?) async throws -> CachedPoster {
        try Task.checkCancellation()
        if let filename, let cached = readLocal(filename) { return cached }
        guard let url = TMDBImageURL.poster(path), let name = Self.filename(for: path) else {
            throw PosterCacheError.noPoster
        }
        if let cached = readLocal(name) { return cached }
        if let task = inFlight[name] { return try await task.value }
        // 共用下载不随某一张卡片消失而取消，其他视图仍可取得同一份文件。
        let task = Task { try await download(url, filename: name) }
        inFlight[name] = task
        defer { inFlight[name] = nil }
        return try await task.value
    }

    nonisolated static func filename(for path: String?) -> String? {
        guard let url = TMDBImageURL.poster(path) else { return nil }
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined() + ".image"
    }

    private func fileURL(_ filename: String) -> URL? {
        // 文件名只接受本应用生成的散列名，不能用相对路径跳出海报目录。
        guard filename.count == 70, filename.hasSuffix(".image"),
              filename.dropLast(6).utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { return nil }
        return directory?.appendingPathComponent(filename, isDirectory: false)
    }

    private func readLocal(_ filename: String) -> CachedPoster? {
        guard let url = fileURL(filename), let data = try? Data(contentsOf: url), Self.isImage(data) else { return nil }
        return CachedPoster(data: data, filename: filename)
    }

    private func download(_ url: URL, filename: String) async throws -> CachedPoster {
        let response = try await transport.send(URLRequest(url: url))
        guard (200..<300).contains(response.statusCode) else { throw PosterCacheError.downloadFailed }
        guard Self.isImage(response.data) else { throw PosterCacheError.invalidImage }
        guard let directory, let destination = fileURL(filename) else { throw PosterCacheError.storageUnavailable }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try response.data.write(to: destination, options: .atomic)
        } catch {
            throw PosterCacheError.storageUnavailable
        }
        return CachedPoster(data: response.data, filename: filename)
    }

    nonisolated private static func isImage(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
    }
}
