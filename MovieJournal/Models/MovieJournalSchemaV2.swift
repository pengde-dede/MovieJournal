import Foundation
import SwiftData

nonisolated enum MovieJournalSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(2, 0, 0) }
    static var models: [any PersistentModel.Type] { [MovieJournalSchemaV1.ViewingRecord.self, EarlierViewing.self] }

    @Model
    final class EarlierViewing {
        var recordID: UUID
        var watchedOn: Date
        var rating: Int
        var review: String
        var season: Int?

        init(recordID: UUID, watchedOn: Date, rating: Int, review: String, season: Int?) {
            self.recordID = recordID
            self.watchedOn = watchedOn
            self.rating = rating
            self.review = review
            self.season = season
        }
    }
}
