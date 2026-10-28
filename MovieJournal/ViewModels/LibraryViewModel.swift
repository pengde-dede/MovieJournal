import Foundation
import Observation

nonisolated struct SavedPosterTarget: Sendable {
    let recordID: UUID
    let path: String?
    let filename: String?
}

@MainActor
@Observable
final class LibraryViewModel {
    var searchText = ""
    var mediaFilter = LibraryMediaFilter.all
    private(set) var isCachingPosters = false
    private(set) var completedPosters = 0
    private(set) var totalPosters = 0
    private(set) var posterMessage: String?
    private(set) var posterReloadToken = 0
    private var cacheRevision = 0

    func matchingRecords(in records: [ViewingRecord]) -> [ViewingRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return records.filter {
            mediaFilter.includes($0.mediaType) && (query.isEmpty
                || $0.title.localizedStandardContains(query) || $0.originalTitle.localizedStandardContains(query))
        }
    }

    func resetFilters() {
        searchText = ""
        mediaFilter = .all
    }

    func cacheSavedPosters(_ targets: [SavedPosterTarget], cache: any PosterCaching, store: RecordStore) async {
        cacheRevision += 1
        let revision = cacheRevision
        let targets = targets.filter { $0.path != nil || $0.filename != nil }
        totalPosters = targets.count
        completedPosters = 0
        posterMessage = nil
        isCachingPosters = !targets.isEmpty
        defer {
            if revision == cacheRevision {
                isCachingPosters = false
                // 重试成功后，已显示占位图的卡片和详情也重新读取本地文件。
                posterReloadToken += 1
            }
        }
        var failures = 0
        var firstError: String?
        for target in targets {
            do {
                try Task.checkCancellation()
                let poster = try await cache.load(path: target.path, filename: target.filename)
                try Task.checkCancellation()
                guard revision == cacheRevision else { return }
                try store.setPosterFilename(poster.filename, recordID: target.recordID, expectedPath: target.path)
            } catch is CancellationError {
                return
            } catch {
                guard revision == cacheRevision else { return }
                failures += 1
                if firstError == nil { firstError = error.localizedDescription }
            }
            completedPosters += 1
        }
        if failures > 0 {
            posterMessage = "\(failures) 张海报暂未保存到本机。\(firstError ?? "") 已保存的文字资料仍可查看；联网后可重试。"
        }
    }
}
