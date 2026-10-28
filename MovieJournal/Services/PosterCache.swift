import CryptoKit
import Foundation
import ImageIO

nonisolated struct CachedPoster: Sendable {
    let data: Data
    let filename: String
    let wasWritten: Bool

    init(data: Data, filename: String, wasWritten: Bool = false) {
        self.data = data
        self.filename = filename
        self.wasWritten = wasWritten
    }
}

nonisolated protocol PosterCaching: Sendable {
    func load(path: String?, filename: String?) async throws -> CachedPoster
}

nonisolated protocol PosterFileManaging: PosterCaching {
    func existingFilename(path: String?, filename: String?) async -> String?
    func readData(filename: String) async throws -> Data
    func cleanupAtStartup(referencedFilenames: Set<String>) async throws -> Int
    func removeUnreferencedFiles(referencedFilenames: Set<String>) async throws -> Int
}

nonisolated enum PosterCacheError: LocalizedError, Equatable, Sendable {
    case noPoster
    case invalidImage
    case downloadFailed
    case storageUnavailable
    case localFileUnavailable
    case cleanupFailed

    var errorDescription: String? {
        switch self {
        case .localFileUnavailable: "本地海报文件暂不可用，联网后可重试补存。"
        case .cleanupFailed: "未能完成海报清理，请稍后点击“重试海报清理”。"
        case .noPoster: "这部作品没有可用的海报。"
        case .invalidImage: "下载的海报无法识别，请稍后重试。"
        case .downloadFailed: "海报暂时无法下载，请稍后重试。"
        case .storageUnavailable: "海报无法保存到本机，请检查可用空间和文件访问权限。"
        }
    }
}

actor PosterCache: PosterFileManaging {
    static let shared = PosterCache()
    private let directory: URL?
    private let transport: any HTTPTransport
    private var didCleanupAtStartup = false
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

    // 仅检查文件元数据，补存规划不读取或解码图片。
    func existingFilename(path: String?, filename: String?) -> String? {
        if let filename, fileExists(filename) { return filename }
        if let expected = Self.filename(for: path), fileExists(expected) { return expected }
        return nil
    }

    // 界面只读本地图片，持久化写入由准备保存和资料库补存负责。
    func readData(filename: String) throws -> Data {
        guard let url = fileURL(filename), let data = try? Data(contentsOf: url) else {
            throw PosterCacheError.localFileUnavailable
        }
        guard PosterImageData.isValid(data) else { throw PosterCacheError.invalidImage }
        return data
    }

    func cleanupAtStartup(referencedFilenames: Set<String>) throws -> Int {
        guard !didCleanupAtStartup else { return 0 }
        didCleanupAtStartup = true
        return try removeUnreferencedFiles(referencedFilenames: referencedFilenames)
    }

    /// 由共享清理管理器调用；数据库先保存，添加窗口全部关闭后再传入最新的剩余引用。
    func removeUnreferencedFiles(referencedFilenames: Set<String>) throws -> Int {
        guard let directory, FileManager.default.fileExists(atPath: directory.path) else { return 0 }
        let retained = referencedFilenames.union(inFlight.keys)
        do {
            let directoryValues = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard directoryValues.isDirectory == true, directoryValues.isSymbolicLink != true else {
                throw PosterCacheError.cleanupFailed
            }
            let files = try FileManager.default.contentsOfDirectory(at: directory,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            var removed = 0
            for file in files where !retained.contains(file.lastPathComponent) {
                let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                // 不遍历子目录，也不跟随符号链接。
                guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
                try FileManager.default.removeItem(at: file)
                removed += 1
            }
            return removed
        } catch {
            throw PosterCacheError.cleanupFailed
        }
    }

    private func fileExists(_ filename: String) -> Bool {
        guard let url = fileURL(filename),
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return false }
        return values.isRegularFile == true && values.isSymbolicLink != true
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
        guard let url = fileURL(filename), let data = try? Data(contentsOf: url), PosterImageData.isValid(data) else { return nil }
        return CachedPoster(data: data, filename: filename)
    }

    private func download(_ url: URL, filename: String) async throws -> CachedPoster {
        let response = try await transport.send(URLRequest(url: url))
        guard (200..<300).contains(response.statusCode) else { throw PosterCacheError.downloadFailed }
        guard PosterImageData.isValid(response.data) else { throw PosterCacheError.invalidImage }
        guard let directory, let destination = fileURL(filename) else { throw PosterCacheError.storageUnavailable }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try response.data.write(to: destination, options: .atomic)
        } catch {
            throw PosterCacheError.storageUnavailable
        }
        return CachedPoster(data: response.data, filename: filename, wasWritten: true)
    }

}

nonisolated enum PosterImageData {
    static func isValid(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
    }
}
