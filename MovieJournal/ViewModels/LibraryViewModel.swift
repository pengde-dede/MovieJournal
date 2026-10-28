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
    private(set) var posterReloadVersions: [String: Int] = [:]
    private(set) var isPreparingLibrary = true
    private(set) var cleanupMessage: String?
    private var didPrepareLibrary = false
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

    func cacheSavedPosters(_ targets: [SavedPosterTarget], cache: any PosterFileManaging, store: RecordStore) async {
        cacheRevision += 1
        let revision = cacheRevision
        totalPosters = 0
        completedPosters = 0
        posterMessage = nil
        isCachingPosters = false
        defer {
            if revision == cacheRevision {
                isCachingPosters = false
                isPreparingLibrary = false
            }
        }
        var missing: [SavedPosterTarget] = []
        do {
            // 首次维护以数据库为准，避免 @Query 尚未显示记录时误把旧海报当作孤立文件。
            let scanTargets: [SavedPosterTarget]
            if didPrepareLibrary {
                scanTargets = targets
            } else {
                scanTargets = try store.recordsNewestFirst().map {
                    SavedPosterTarget(recordID: $0.id, path: $0.posterPath, filename: $0.posterFilename)
                }
            }
            for target in scanTargets where target.path != nil || target.filename != nil {
                let existing = await cache.existingFilename(path: target.path, filename: target.filename)
                try Task.checkCancellation()
                guard revision == cacheRevision else { return }
                if let existing {
                    // 兼容旧记录：文件已经存在时只补充引用，不读取图片，也不触发刷新。
                    if target.filename != existing {
                        try store.setPosterFilename(existing, recordID: target.recordID, expectedPath: target.path)
                    }
                } else {
                    missing.append(target)
                }
            }
            if !didPrepareLibrary {
                let references = Set(try store.recordsNewestFirst().compactMap(\.posterFilename))
                do { _ = try await cache.cleanupAtStartup(referencedFilenames: references) }
                catch { cleanupMessage = error.localizedDescription }
                try Task.checkCancellation()
                guard revision == cacheRevision else { return }
                didPrepareLibrary = true
            }
        } catch is CancellationError {
            return
        } catch {
            // 无法确认数据库引用时不执行清理，避免移除仍然需要的图片。
            didPrepareLibrary = true
            posterMessage = "无法检查本地海报：\(error.localizedDescription)"
            return
        }
        isPreparingLibrary = false
        totalPosters = missing.count
        guard !missing.isEmpty else { return }
        isCachingPosters = true
        var failures = 0
        var firstError: String?
        for target in missing {
            do {
                try Task.checkCancellation()
                let poster = try await cache.load(path: target.path, filename: target.filename)
                try Task.checkCancellation()
                guard revision == cacheRevision else { return }
                try store.setPosterFilename(poster.filename, recordID: target.recordID, expectedPath: target.path)
                if poster.wasWritten {
                    posterReloadVersions[poster.filename, default: 0] += 1
                }
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
