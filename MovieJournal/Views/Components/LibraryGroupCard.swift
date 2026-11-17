import AppKit
import SwiftUI

struct LibraryGroupCard: View {
    let group: LibraryGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LibraryGroupCover(path: group.artworkPath, usesProfile: group.usesProfile,
                              symbolName: group.symbolName, sources: group.posterSources)
                .accessibilityHidden(true)
            Text(group.name).font(.headline).lineLimit(2)
            Label(group.records.count == group.libraryCount ? "\(group.libraryCount) 部电影"
                  : "\(group.records.count) / \(group.libraryCount) 部电影", systemImage: group.symbolName)
                .font(.caption.weight(.medium)).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct LibraryGroupCover: View {
    let path: String?
    let usesProfile: Bool
    let symbolName: String
    let sources: [ViewingRecord]
    @Environment(\.posterCache) private var cache
    @State private var artwork: NSImage?
    @State private var artworkPath: String?

    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(.quaternary)
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .overlay {
                if artworkPath == path, let artwork {
                    Image(nsImage: artwork).resizable().scaledToFill()
                } else {
                    collage
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: symbolName)
                    .font(.footnote.weight(.semibold))
                    .padding(7)
                    .foregroundStyle(.white)
                    .background(.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 7))
                    .padding(8)
            }
            .task(id: path) {
                guard let path else { return }
                do {
                    let poster: CachedPoster
                    if usesProfile {
                        poster = try await cache.loadProfile(path: path)
                    } else {
                        poster = try await cache.load(path: path, filename: nil)
                    }
                    try Task.checkCancellation()
                    if let image = NSImage(data: poster.data) {
                        artwork = image
                        artworkPath = path
                    }
                } catch {
                    // 沿用影片海报拼图，本次下载失败后仍可浏览合集。
                }
            }
    }

    @ViewBuilder
    private var collage: some View {
        if sources.isEmpty {
            Image(systemName: symbolName).font(.largeTitle).foregroundStyle(.secondary)
        } else if sources.count == 1, let source = sources.first {
            PosterView(path: source.posterPath, filename: source.posterFilename)
        } else {
            GeometryReader { geometry in
                let width = geometry.size.width / 2
                let height = sources.count == 4 ? geometry.size.height / 2 : geometry.size.height
                LazyVGrid(columns: [GridItem(.fixed(width), spacing: 0), GridItem(.fixed(width), spacing: 0)], spacing: 0) {
                    ForEach(sources.prefix(sources.count == 4 ? 4 : 2)) { record in
                        PosterView(path: record.posterPath, filename: record.posterFilename)
                            .frame(width: height * 2 / 3, height: height)
                            .frame(width: width, height: height)
                            .clipped()
                    }
                }
            }
        }
    }
}
