import AppKit
import SwiftUI

nonisolated private struct PosterCacheKey: EnvironmentKey {
    static let defaultValue: any PosterFileManaging = PosterCache.shared
}
nonisolated private struct PosterThumbnailKey: EnvironmentKey {
    static let defaultValue: any PosterThumbnailLoading = PosterThumbnailCache.shared
}
nonisolated private struct PosterReloadKey: EnvironmentKey {
    static let defaultValue: [String: Int] = [:]
}

extension EnvironmentValues {
    var posterCache: any PosterFileManaging {
        get { self[PosterCacheKey.self] }
        set { self[PosterCacheKey.self] = newValue }
    }
    var posterThumbnails: any PosterThumbnailLoading {
        get { self[PosterThumbnailKey.self] }
        set { self[PosterThumbnailKey.self] = newValue }
    }
    var posterReloadVersions: [String: Int] {
        get { self[PosterReloadKey.self] }
        set { self[PosterReloadKey.self] = newValue }
    }
}

// 候选缩略图只进入 w185 内存缓存。
struct SearchPosterView: View {
    let path: String?
    @Environment(\.posterThumbnails) private var thumbnails

    var body: some View {
        PosterImageView(request: PosterImageRequest(identity: TMDBImageURL.poster(path, small: true)?.absoluteString,
            reference: nil, version: 0), small: true) {
                try await thumbnails.load(path: path)
            }
    }
}

// 已保存作品和准备保存的作品只在这里读取本地文件，不由视图发起持久化下载。
struct PosterView: View {
    let path: String?
    var filename: String? = nil
    @Environment(\.posterCache) private var cache
    @Environment(\.posterReloadVersions) private var versions

    var body: some View {
        let localName = filename ?? PosterCache.filename(for: path)
        PosterImageView(request: PosterImageRequest(identity: localName, reference: filename,
            version: localName.map { versions[$0, default: 0] } ?? 0)) {
                guard let localName else { throw PosterCacheError.noPoster }
                return try await cache.readData(filename: localName)
            }
    }
}

nonisolated private struct PosterImageRequest: Hashable {
    let identity: String?
    let reference: String?
    let version: Int
}

private struct PosterImageView: View {
    let request: PosterImageRequest
    var small = false
    let loadData: @MainActor () async throws -> Data
    @State private var image: NSImage?
    @State private var currentIdentity: String?
    @State private var loadedVersion: Int?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(.quaternary)
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .overlay {
                if let image {
                    Image(nsImage: image).resizable().scaledToFill()
                } else if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "film").font(small ? .title3 : .largeTitle)
                        if !small { Text(errorMessage == nil ? "暂无海报" : "海报暂不可用").font(.caption) }
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .help(errorMessage ?? "影片海报")
            .accessibilityLabel(image == nil ? "暂无海报" : "影片海报")
            .task(id: request) { await load() }
    }

    private func load() async {
        if currentIdentity != request.identity {
            image = nil
            currentIdentity = request.identity
            loadedVersion = nil
        }
        guard request.identity != nil else { isLoading = false; return }
        // 同一图片只补充了数据库引用时不重复读取；真正刷新时也保留旧图，避免闪烁。
        if image != nil, loadedVersion == request.version { return }
        errorMessage = nil
        isLoading = image == nil
        do {
            let data = try await loadData()
            try Task.checkCancellation()
            guard let decoded = NSImage(data: data) else { throw PosterCacheError.invalidImage }
            image = decoded
            loadedVersion = request.version
        } catch {
            guard !Task.isCancelled else { return }
            if !(error is CancellationError) { errorMessage = error.localizedDescription }
        }
        if !Task.isCancelled { isLoading = false }
    }
}
