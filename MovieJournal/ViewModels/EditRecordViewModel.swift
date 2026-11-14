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

    let isRewatch: Bool

    init(record: ViewingRecord, store: RecordStore, isRewatch: Bool = false) {
        self.isRewatch = isRewatch
        recordID = record.id
        draft = isRewatch ? RecordDraft(details: MediaDetails(record: record)) : RecordDraft(record: record)
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
            if isRewatch {
                try store.addViewing(recordID: recordID, draft: draft)
            } else {
                try store.updatePersonalInformation(recordID: recordID, watchedOn: draft.watchedOn,
                    myRating: rating, shortReview: draft.shortReview, watchedSeason: draft.watchedSeason)
            }
            didSave = true
            return true
        } catch {
            saveError = "修改未能保存：\(error.localizedDescription)"
            return false
        }
    }
}
