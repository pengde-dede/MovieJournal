import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class PersistenceController {
    private(set) var container: ModelContainer?
    private(set) var errorDescription: String?

    func loadIfNeeded() {
        guard container == nil, errorDescription == nil else { return }
        reload()
    }

    func reload() {
        do {
            container = try Self.makeContainer()
            errorDescription = nil
        } catch {
            container = nil
            errorDescription = error.localizedDescription
        }
    }

    /// 测试传入独立临时目录；正式应用使用沙盒内的 Application Support。
    static func makeContainer(in directory: URL? = nil) throws -> ModelContainer {
        let storageDirectory: URL
        if let directory {
            storageDirectory = directory
        } else {
            let applicationSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            storageDirectory = applicationSupport.appendingPathComponent("MovieJournal", isDirectory: true)
        }

        try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)

        let schema = Schema(versionedSchema: MovieJournalSchemaV1.self)
        let configuration = ModelConfiguration(
            "MovieJournal",
            schema: schema,
            url: storageDirectory.appendingPathComponent("MovieJournal.store"),
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: MovieJournalMigrationPlan.self,
            configurations: [configuration]
        )
        // 保存入口显式调用 save，以便出错时向用户报告失败。
        container.mainContext.autosaveEnabled = false
        return container
    }
}
