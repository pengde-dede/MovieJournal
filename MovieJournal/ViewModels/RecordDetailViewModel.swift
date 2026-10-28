import Foundation
import Observation

struct RecordDeletionRequest {
    let id: UUID
    let title: String
}

@MainActor
@Observable
final class RecordDetailViewModel {
    var isShowingDeleteConfirmation = false
    private(set) var deletionRequest: RecordDeletionRequest?
    private(set) var deleteError: String?

    func requestDeletion(id: UUID, title: String) {
        deleteError = nil
        deletionRequest = RecordDeletionRequest(id: id, title: title)
        isShowingDeleteConfirmation = true
    }

    func cancelDeletion() {
        isShowingDeleteConfirmation = false
        deletionRequest = nil
    }

    func confirmDeletion(store: RecordStore, cleanup: PosterCleanupCoordinator) -> Bool {
        guard let request = deletionRequest else { return false }
        cancelDeletion()
        do {
            try store.delete(recordID: request.id)
            cleanup.requestCleanup(store: store)
            return true
        } catch {
            deleteError = "删除未能完成：\(error.localizedDescription)"
            return false
        }
    }
}
