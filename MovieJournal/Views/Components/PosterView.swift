import AppKit
import SwiftUI

nonisolated private struct PosterCacheKey: EnvironmentKey {
    static let defaultValue: any PosterCaching = PosterCache.shared
}
nonisolated private struct PosterReloadKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    var posterCache: any PosterCaching {
        get { self[PosterCacheKey.self] }
        set { self[PosterCacheKey.self] = newValue }
    }
    var posterReloadToken: Int {
        get { self[PosterReloadKey.self] }
        set { self[PosterReloadKey.self] = newValue }
    }
}

struct PosterView: View {
    let path: String?
    var filename: String? = nil
    var small = false
    @Environment(\.posterCache) private var cache
    @Environment(\.posterReloadToken) private var reloadToken
    @State private var image: NSImage?
    @State private var isLoading = false
    @State private var errorMessage: String?

    nonisolated private struct RequestID: Hashable {
        let path: String?
        let filename: String?
        let reloadToken: Int
    }

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
                        if !small {
                            Text(errorMessage == nil ? "暂无海报" : "海报暂不可用").font(.caption)
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .help(errorMessage ?? "影片海报")
            .accessibilityLabel(image == nil ? "暂无海报" : "影片海报")
            .task(id: RequestID(path: path, filename: filename, reloadToken: reloadToken)) {
                await load()
            }
    }

    private func load() async {
        image = nil
        errorMessage = nil
        guard path != nil || filename != nil else { isLoading = false; return }
        isLoading = true
        do {
            let poster = try await cache.load(path: path, filename: filename)
            try Task.checkCancellation()
            guard let decoded = NSImage(data: poster.data) else { throw PosterCacheError.invalidImage }
            image = decoded
        } catch {
            guard !Task.isCancelled else { return }
            if !(error is CancellationError) { errorMessage = error.localizedDescription }
        }
        if !Task.isCancelled { isLoading = false }
    }
}
