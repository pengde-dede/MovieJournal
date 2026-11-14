import SwiftData

nonisolated enum MovieJournalMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [MovieJournalSchemaV1.self, MovieJournalSchemaV2.self] }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: MovieJournalSchemaV1.self, toVersion: MovieJournalSchemaV2.self)]
    }
}
