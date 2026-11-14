import CoreData
import Foundation
import SQLite3

enum PreMigrationBackup {
    // A single SQLite snapshot includes committed WAL pages and can be opened by V1.
    static func preserveV1(at store: URL) throws {
        let files = FileManager.default
        let folder = store.deletingLastPathComponent().appendingPathComponent("Backups", isDirectory: true)
        let destination = folder.appendingPathComponent("BeforeV2.store")
        guard files.fileExists(atPath: store.path), !files.fileExists(atPath: destination.path) else { return }
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType, at: store)
        guard let hashes = metadata[NSStoreModelVersionHashesKey] as? [String: Data],
              hashes["ViewingRecord"] != nil, hashes["EarlierViewing"] == nil else { return }
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        let temporary = folder.appendingPathComponent(UUID().uuidString)
        defer { try? files.removeItem(at: temporary) }
        try copyDatabase(from: store, to: temporary)
        try files.moveItem(at: temporary, to: destination)
    }

    // Read the on-disk columns before opening the new schema. This also supports a V1 → V3 jump.
    static func preserveBeforeV3(at store: URL) throws {
        let files = FileManager.default
        guard files.fileExists(atPath: store.path) else { return }
        var database: OpaquePointer?
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement); sqlite3_close(database) }
        guard sqlite3_open_v2(store.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              sqlite3_prepare_v2(database, "SELECT name FROM pragma_table_info('ZVIEWINGRECORD')", -1, &statement, nil) == SQLITE_OK
        else { throw Failure.snapshot }
        var columns: Set<String> = []
        var step = sqlite3_step(statement)
        while step == SQLITE_ROW {
            if let text = sqlite3_column_text(statement, 0) { columns.insert(String(cString: text).uppercased()) }
            step = sqlite3_step(statement)
        }
        guard step == SQLITE_DONE, !columns.isEmpty else { throw Failure.snapshot }
        guard !columns.contains("ZWATCHSTATUSRAWVALUE") else { return }
        let folder = store.deletingLastPathComponent().appendingPathComponent("Backups", isDirectory: true)
        let destination = folder.appendingPathComponent("BeforeV3.store")
        guard !files.fileExists(atPath: destination.path) else { return }
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        let temporary = folder.appendingPathComponent(UUID().uuidString)
        defer { try? files.removeItem(at: temporary) }
        try copyDatabase(from: store, to: temporary)
        try files.moveItem(at: temporary, to: destination)
    }

    private static func copyDatabase(from source: URL, to target: URL) throws {
        var input: OpaquePointer?
        var output: OpaquePointer?
        defer { sqlite3_close(output); sqlite3_close(input) }
        guard sqlite3_open_v2(source.path, &input, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              sqlite3_open_v2(target.path, &output, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE, nil) == SQLITE_OK,
              let job = sqlite3_backup_init(output, "main", input, "main") else { throw Failure.snapshot }
        let result = sqlite3_backup_step(job, -1)
        let finished = sqlite3_backup_finish(job)
        guard result == SQLITE_DONE, finished == SQLITE_OK else { throw Failure.snapshot }
    }

    enum Failure: LocalizedError {
        case snapshot
        var errorDescription: String? { "无法创建升级前的数据库备份，请检查磁盘空间并重试。" }
    }
}
