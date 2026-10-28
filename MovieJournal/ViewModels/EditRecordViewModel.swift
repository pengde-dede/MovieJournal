import Foundation
import Observation

@MainActor
@Observable
final class EditRecordViewModel {
    let recordID: UUID
    var draft: RecordDraft
    private let store: RecordStore
    private(set) var saveError: String?
    private(set) var didSave = false

    init(record: ViewingRecord, store: RecordStore) {
        recordID = record.id
        draft = RecordDraft(record: record)
        self.store = store
    }

    func save() -> Bool {
        guard !didSave else { return false }
        saveError = nil
        if let message = draft.validationMessage {
            saveError = message
            return false
        }
        guard let rating = draft.myRating else { return false }
        do {
            try store.updatePersonalInformation(recordID: recordID, watchedOn: draft.watchedOn,
                myRating: rating, shortReview: draft.shortReview, watchedSeason: draft.watchedSeason)
            didSave = true
            return true
        } catch {
            saveError = "修改未能保存：\(error.localizedDescription)"
            return false
        }
    }
}
