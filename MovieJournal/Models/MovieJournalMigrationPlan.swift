import Foundation
import SwiftData

nonisolated enum MovieJournalMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [MovieJournalSchemaV1.self, MovieJournalSchemaV2.self, MovieJournalSchemaV3.self, MovieJournalSchemaV4.self]
    }

    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: MovieJournalSchemaV1.self, toVersion: MovieJournalSchemaV2.self),
         .lightweight(fromVersion: MovieJournalSchemaV2.self, toVersion: MovieJournalSchemaV3.self),
         .custom(fromVersion: MovieJournalSchemaV3.self, toVersion: MovieJournalSchemaV4.self,
                 willMigrate: nil, didMigrate: assignViewingIDs)]
    }

    private static func assignViewingIDs(in context: ModelContext) throws {
        let history = try context.fetch(FetchDescriptor<MovieJournalSchemaV4.EarlierViewing>())
        let owners = Set(history.map(\.recordID))
        for viewing in history where viewing.viewingID == nil {
            viewing.viewingID = UUID()
        }
        for record in try context.fetch(FetchDescriptor<MovieJournalSchemaV4.ViewingRecord>()) {
            record.assignLatestViewingIDIfNeeded(hasHistory: owners.contains(record.id))
        }
        try context.save()
    }
}
