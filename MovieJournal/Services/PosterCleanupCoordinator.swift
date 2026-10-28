import Foundation
import Observation

/// 所有窗口共用。添加窗口打开期间推迟清理，关闭最后一个窗口后重新读取数据库引用。
@MainActor
@Observable
final class PosterCleanupCoordinator {
    private let cache: any PosterFileManaging
    private var addingSessions: Set<UUID> = []
    private var didRequestStartup = false
    private var startupRequested = false
    private(set) var isCleanupPending = false
    private(set) var isCleaning = false
    private(set) var cleanupMessage: String?
    @ObservationIgnored private(set) var cleanupTask: Task<Void, Never>?

    init(cache: any PosterFileManaging) { self.cache = cache }

    func beginAdding() -> UUID? {
        // 清理从读取引用到实际删文件之间，不允许开始新的添加；检查和登记同在主线程。
        guard !isCleaning else { return nil }
        let session = UUID()
        addingSessions.insert(session)
        return session
    }

    func finishAdding(_ session: UUID, store: RecordStore) {
        guard addingSessions.remove(session) != nil else { return }
        scheduleIfPossible(store: store)
    }

    func cleanupAtStartup(store: RecordStore) async {
        if !didRequestStartup {
            didRequestStartup = true
            startupRequested = true
            isCleanupPending = true
            scheduleIfPossible(store: store)
        }
        await cleanupTask?.value
    }

    // 只在记录已成功删除并保存后调用；失败重试也使用最新的数据库引用。
    func requestCleanup(store: RecordStore) {
        isCleanupPending = true
        cleanupMessage = nil
        scheduleIfPossible(store: store)
    }

    private func scheduleIfPossible(store: RecordStore) {
        guard isCleanupPending, addingSessions.isEmpty, cleanupTask == nil else { return }
        isCleaning = true
        cleanupTask = Task { [weak self] in
            guard let self else { return }
            defer { isCleaning = false; cleanupTask = nil }
            // 清理等待期间若另一窗口又删除记录，再用新引用补做一次。
            while isCleanupPending {
                let isStartup = startupRequested
                startupRequested = false
                isCleanupPending = false
                do {
                    let records = try store.recordsNewestFirst()
                    // 补存下载返回与引用回写之间也要保留文件；文件名可直接由海报路径推导，无需读图。
                    let references = Set(records.flatMap { record in
                        [record.posterFilename, PosterCache.filename(for: record.posterPath)].compactMap { $0 }
                    })
                    if isStartup {
                        _ = try await cache.cleanupAtStartup(referencedFilenames: references)
                    } else {
                        _ = try await cache.removeUnreferencedFiles(referencedFilenames: references)
                    }
                    cleanupMessage = nil
                } catch {
                    // 不能确认引用时直接跳过；清理失败也不撤销已经成功的记录操作。
                    cleanupMessage = "海报清理暂未完成，现有记录已保留。\(error.localizedDescription)"
                }
            }
        }
    }
}
