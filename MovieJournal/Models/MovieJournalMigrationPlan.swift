import SwiftData

nonisolated enum MovieJournalMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [MovieJournalSchemaV1.self] }

    // 当前只有 V1；将来添加 V2 时在这里声明迁移路径。
    static var stages: [MigrationStage] { [] }
}
